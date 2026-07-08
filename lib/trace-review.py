#!/usr/bin/env python3
"""devflow trace-review engine - per-skill week-over-week Langfuse regression analysis.

READ-ONLY. Pulls traces/observations/scores from a self-hosted Langfuse, attributes
each trace to a skill via a precedence ladder, compares a rolling "this week" vs
"last week" window, flags regressions against balanced thresholds, and emits a JSON
document.

Why this exists (baseline failure it fixes): a cold agent assumes a `skill.name`
trace field, when the real key is `skill_name` and it lands on `claude_code.tool`
spans (NOT on the child `claude_code.tool.execution` span). The join here scans every
observation on the trace, so it finds skill_name wherever it sits. It also naively sums
cost/latency across mixed span types (interaction wall-clock + llm latency) which
inflates totals. This engine joins by traceId and uses Langfuse's already-aggregated
per-trace `totalCost`/`latency`, so the numbers are correct and reproducible.

Attribution ladder (best signal wins, per trace):
  1. skill_name    - the `skill_name` attribute on any span (Claude Code stamps it on
                     the `claude_code.tool` span, incl. `tool_name=='Skill'` spans).
  2. slash_command - a leading-slash `user_prompt` on the interaction span (a user who
                     typed `/devflow:review ...`); the first token (minus the slash) is
                     the skill. Recovers skills that ran without a skill_name span.
  3. hook_sidecar  - a `session_id + timestamp` window join against the enrichment hook's
                     JSONL (see lib/hooks/skill-activation-log.sh, registered by
                     `devflow init`). Because one Langfuse trace == one Claude Code
                     interaction (many per session), the join attributes each trace to
                     the LATEST skill invocation at-or-before that trace's timestamp in
                     the same session - a flat session->skill map would mis-attribute
                     every turn of a multi-skill session. This rung is forward-only: it
                     can only attribute traces produced after the hook is installed.
                     Two known heuristic limits: (a) it PROPAGATES, it does not backfill
                     - the skill's own invocation turn is caught by rung 1 (skill_name on
                     the Skill span); rung 3 carries that skill forward to later turns.
                     (b) it attributes ALL subsequent same-session turns to the last
                     skill until another fires, so unrelated work a user pivots to
                     mid-session is charged to that skill (can surface as a phantom cost
                     regression). No finer signal exists; documented, not hidden.

Coverage caveat: a trace that matches no rung buckets into "(unattributed)" (ordinary
tool activity with no skill marker). That bucket is kept in the totals for honesty but
held OUT of the per-skill regression ranking (it is not a skill). The report prints the
per-source attribution breakdown so thin coverage is visible, not hidden.

Output: a single JSON object on stdout. The skill renders it to markdown from a
pinned template. No AI judgement in here - pure deterministic aggregation.
"""
import sys, os, json, base64, urllib.request, urllib.parse, urllib.error
from collections import Counter
from datetime import datetime, timedelta, timezone

# ── Config (balanced thresholds; overridable via env) ──
ERR_RATE_UP_PP = float(os.environ.get("TRACE_REVIEW_ERR_RATE_UP_PP", "10")) / 100.0  # +10 percentage points
SCORE_DOWN     = float(os.environ.get("TRACE_REVIEW_SCORE_DOWN", "0.05"))            # -0.05 absolute
COST_UP_PCT    = float(os.environ.get("TRACE_REVIEW_COST_UP_PCT", "25")) / 100.0     # +25%
LAT_UP_PCT     = float(os.environ.get("TRACE_REVIEW_LAT_UP_PCT", "25")) / 100.0      # +25% (p95)
WINDOW_DAYS    = int(os.environ.get("TRACE_REVIEW_WINDOW_DAYS", "7"))

UNATTRIBUTED = "(unattributed)"


def _die(msg, code=1):
    # stderr, NOT stdout: a caller redirecting stdout to a report file must not end up
    # with the error JSON written into that file when the run fails.
    print(json.dumps({"error": msg}), file=sys.stderr)
    sys.exit(code)


def _api(host, auth_b64, path, params):
    qs = urllib.parse.urlencode(params)
    url = f"{host}/api/public/{path}?{qs}"
    req = urllib.request.Request(url, headers={"Authorization": f"Basic {auth_b64}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def _paginate(host, auth_b64, path, params, hard_cap=20000):
    """Page through a list endpoint. Langfuse list endpoints use page/limit.

    A missing `meta` block is treated as an error rather than "one page" - the latter
    would silently truncate the whole dataset to the first 100 rows with no signal.
    Hitting `hard_cap` mid-dataset also warns (to stderr) so a partial pull is never
    mistaken for a complete one.
    """
    out, page = [], 1
    while len(out) < hard_cap:
        p = dict(params); p["limit"] = 100; p["page"] = page
        d = _api(host, auth_b64, path, p)
        rows = d.get("data") or []
        out.extend(rows)
        meta = d.get("meta")
        if not isinstance(meta, dict) or "totalPages" not in meta:
            raise ValueError(f"{path}: response missing pagination meta - cannot page safely")
        total_pages = meta.get("totalPages") or 1
        if page >= total_pages or not rows:
            break
        page += 1
    if len(out) >= hard_cap:
        print(json.dumps({"warning": f"{path}: hit hard_cap={hard_cap}; results truncated, "
                                     "aggregates are partial. Narrow --window."}), file=sys.stderr)
    return out


def _attr(obs, key):
    md = obs.get("metadata") or {}
    a = md.get("attributes") or {}
    if key in a:
        return a[key]
    r = md.get("resourceAttributes") or {}
    return r.get(key)


def _pct(values, q):
    if not values:
        return None
    s = sorted(values)
    if len(s) == 1:
        return s[0]
    # nearest-rank percentile, deterministic
    k = max(0, min(len(s) - 1, int(round((q / 100.0) * (len(s) - 1)))))
    return s[k]


# Claude Code built-in slash commands are NOT skills. Attributing them would pollute the
# per-skill ranking with phantom rows (a session that runs /compact would otherwise show
# a "compact" skill). Mirror the write-side hook (lib/hooks/skill-activation-log.sh),
# which uses PreToolUse:Skill precisely to avoid recording these.
BUILTIN_SLASH = {
    "compact", "clear", "config", "model", "help", "review", "init", "cost", "quit",
    "exit", "resume", "logout", "login", "status", "doctor", "memory", "vim", "agents",
    "mcp", "hooks", "permissions", "context", "export", "bug", "release-notes", "add-dir",
    "terminal-setup", "ide", "pr-comments", "fast",
}


def _slash_skill(obs_list):
    """Skill parsed from a leading-slash `user_prompt` on any of the trace's spans.

    A user prompt like "/devflow:review run" -> "devflow:review" (first token, slash
    stripped). Built-in Claude Code commands (see BUILTIN_SLASH) are skipped so they fall
    through to (unattributed) instead of ranking as phantom skills. Returns None when no
    span carries a leading-slash user_prompt that names a skill.
    """
    for o in obs_list:
        up = _attr(o, "user_prompt")
        if isinstance(up, str):
            s = up.strip()
            if s.startswith("/") and len(s) > 1:
                tok = s[1:].split()[0]
                if tok and tok.lower() not in BUILTIN_SLASH:
                    return tok
    return None


def _load_sidecar(path):
    """session_id -> sorted [(ts, skill)] from the enrichment hook's JSONL log.

    Each line is a JSON object {"session_id","ts","skill"}. Malformed lines are skipped
    (the reader must never abort on a truncated tail the hook was mid-write on). A
    missing/empty file yields an empty map (the sidecar rung is then inert).

    Note: reads the whole file each run and the sidecar does not self-rotate. Fine at
    current volume; if it grows unbounded over months, cap or rotate it (rows older than
    the analysis window are never consulted)."""
    m = {}
    if not path or not os.path.exists(path):
        return m
    try:
        fh = open(path, encoding="utf-8")
    except OSError:
        return m
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except (ValueError, TypeError):
                continue
            sid, ts, sk = r.get("session_id"), _parse_ts(r.get("ts")), r.get("skill")
            if sid and ts and sk:
                m.setdefault(sid, []).append((ts, sk))
    for sid in m:
        m[sid].sort(key=lambda x: x[0])
    return m


def _sidecar_skill(sidecar, session_id, trace_ts):
    """Latest skill invoked at-or-before trace_ts within the same session (None if none).

    Interaction-grained: one session runs many skills across turns, so we bind a trace to
    the skill whose invocation timestamp is the greatest <= the trace's timestamp."""
    if not session_id or trace_ts is None:
        return None
    best = None
    for ts, sk in sidecar.get(session_id, []):
        if ts <= trace_ts:
            best = sk
        else:
            break
    return best


def _attribute_traces(traces, obs_by_trace, sidecar=None):
    """Attribute each trace to a skill via the precedence ladder (see module docstring).

    Returns (skill_map, source_map): traceId -> skill, and traceId -> which rung won
    ("skill_name" | "slash_command" | "hook_sidecar"). Unmatched traces appear in
    neither map and bucket into (unattributed) downstream.
    """
    skill_map, source_map = {}, {}
    sidecar = sidecar or {}
    for t in traces:
        tid = t.get("id")
        if not tid:
            continue
        ol = obs_by_trace.get(tid, [])
        skill = source = None
        # rung 1: skill_name attribute (first span that carries it)
        for o in ol:
            sn = _attr(o, "skill_name")
            if sn:
                skill, source = sn, "skill_name"
                break
        # rung 2: leading-slash user_prompt
        if not skill:
            sk = _slash_skill(ol)
            if sk:
                skill, source = sk, "slash_command"
        # rung 3: session + timestamp sidecar window (forward-only enrichment)
        if not skill:
            sk = _sidecar_skill(sidecar, t.get("sessionId"), _parse_ts(t.get("timestamp")))
            if sk:
                skill, source = sk, "hook_sidecar"
        if skill:
            skill_map[tid] = skill
            source_map[tid] = source
    return skill_map, source_map


def _trace_exec_stats(tid, obs_by_trace):
    """Per-execution error stats for a trace, counted at TOOL-EXECUTION granularity.

    Returns (total_executions, failed_executions). We count only
    claude_code.tool.execution spans; a failed one is success=='false', ERROR
    level, or carries an `error` attr. Permission gates (claude_code.tool.blocked_on_user,
    decision=reject) are NOT tool executions and never count as errors, so a user
    declining a tool call is not a skill regression. Per-execution (not per-trace) so a
    single failed shell command in a long session does not push the skill to 100%.
    """
    total = failed = 0
    for o in obs_by_trace.get(tid, []):
        if o.get("name") != "claude_code.tool.execution":
            continue
        total += 1
        succ = _attr(o, "success")
        if (str(o.get("level") or "").upper() == "ERROR"
                or (succ is not None and str(succ).lower() == "false")
                or _attr(o, "error")):
            failed += 1
    return total, failed


def _trace_tokens(tid, obs_by_trace):
    total = 0
    for o in obs_by_trace.get(tid, []):
        u = o.get("usage") or {}
        total += int(u.get("total") or 0)
    return total


def _eval_trace_skill(t):
    """Skill a devflow-eval trace belongs to, or None if the trace is not an eval trace.

    An eval trace is a per-skill-version quality run (promptfoo bench, tessl review)
    pushed by eval/lib/langfuse-push.sh — NOT a production skill activation. It is
    tagged `devflow-eval` (or metadata.devflow_eval) and names its skill via
    metadata.skill_name or a `skill:<name>` tag."""
    tags = t.get("tags") or []
    md = t.get("metadata") or {}
    if "devflow-eval" not in tags and not md.get("devflow_eval"):
        return None
    sk = md.get("skill_name")
    if not sk:
        for tag in tags:
            if isinstance(tag, str) and tag.startswith("skill:"):
                sk = tag[len("skill:"):]
                break
    return sk or None


def _build_eval_scores(traces, scores_by_trace):
    """(eval_scores_by_skill, eval_trace_ids) from devflow-eval traces.

    Quality scores (promptfoo pass-rate, tessl review) are per-skill-version, not
    production-trace annotations, so they can never join to a production trace's id.
    Key them by skill + timestamp instead, carrying the score NAME (so different score
    types are not averaged together downstream), and return the eval trace ids so the
    caller can hold those traces OUT of the production cost/latency/count aggregation.
    Entries are (ts, name, value)."""
    by_skill, eval_ids = {}, set()
    for t in traces:
        sk = _eval_trace_skill(t)
        if not sk:
            continue
        tid = t.get("id")
        if not tid:
            continue
        eval_ids.add(tid)
        ts = _parse_ts(t.get("timestamp"))
        if ts is None:
            continue
        for (nm, v) in scores_by_trace.get(tid, []):
            by_skill.setdefault(sk, []).append((ts, nm, v))
    for sk in by_skill:
        by_skill[sk].sort(key=lambda x: x[0])
    return by_skill, eval_ids


# When several score types coexist for a skill in a window, average only ONE type (never
# mix e.g. a binary promptfoo pass/fail with a graded tessl review, which yields a
# meaningless mean). Prefer the varying quality signal; fall back deterministically.
SCORE_PREFERENCE = ("tessl_review", "assert_pass")
# Short column/flag labels per score type (the two split columns + any future type).
SCORE_LABEL = {"tessl_review": "review", "assert_pass": "pass-rate"}


def _preferred_mean(named_scores):
    """(mean, n, kind) over a single score name chosen from [(name, value), ...].

    Picks the first name in SCORE_PREFERENCE that is present, else the alphabetically
    first name (deterministic). Returns (None, 0, None) when there are no scores."""
    if not named_scores:
        return None, 0, None
    by_name = {}
    for nm, v in named_scores:
        by_name.setdefault(nm or "score", []).append(v)
    for pref in SCORE_PREFERENCE:
        if pref in by_name:
            vals = by_name[pref]
            return sum(vals) / len(vals), len(vals), pref
    nm = sorted(by_name)[0]
    vals = by_name[nm]
    return sum(vals) / len(vals), len(vals), nm


def _means_by_kind(named_scores):
    """{name: {"mean": x, "n": k}} over [(name, value), ...], one entry per score type.

    Unlike _preferred_mean (which collapses to a single type), this keeps every type so
    the report can show tessl review and promptfoo pass-rate as SEPARATE columns, each
    with its own trend."""
    by_name = {}
    for nm, v in named_scores:
        by_name.setdefault(nm or "score", []).append(v)
    return {nm: {"mean": sum(vals) / len(vals), "n": len(vals)} for nm, vals in by_name.items()}


def _aggregate(traces, obs_by_trace, trace_skill, scores_by_trace, lo, hi, eval_scores_by_skill=None):
    """Aggregate per skill for traces whose timestamp is in [lo, hi).

    A skill's mean_score pools (a) production-trace scores joined by traceId and (b) eval
    scores for that skill whose timestamp falls in the window, then averages only ONE
    score type via _preferred_mean (never mixing e.g. tessl review with promptfoo
    pass/fail). score_kind names which type was used. Eval scores augment skills already
    present in the production aggregation; a skill with eval scores but zero production
    traces in-window is not surfaced (there is no cost/latency/count to rank it by)."""
    agg = {}
    for t in traces:
        ts = _parse_ts(t.get("timestamp"))
        tid = t.get("id")
        if tid is None or ts is None or not (lo <= ts < hi):
            continue
        skill = trace_skill.get(tid, UNATTRIBUTED)
        a = agg.setdefault(skill, {
            "count": 0, "exec_total": 0, "exec_failed": 0, "latencies": [], "cost": 0.0,
            "tokens": 0, "scores": [], "exemplar_error": None, "exemplar_cost": None,
            "max_cost": -1.0,
        })
        a["count"] += 1
        ex_total, ex_failed = _trace_exec_stats(tid, obs_by_trace)
        a["exec_total"] += ex_total
        a["exec_failed"] += ex_failed
        if ex_failed and a["exemplar_error"] is None:
            a["exemplar_error"] = tid
        lat = t.get("latency")
        if isinstance(lat, (int, float)):
            a["latencies"].append(float(lat))
        cost = float(t.get("totalCost") or 0.0)
        a["cost"] += cost
        if cost > a["max_cost"]:
            a["max_cost"] = cost
            a["exemplar_cost"] = tid
        a["tokens"] += _trace_tokens(tid, obs_by_trace)
        # production-trace scores arrive as (name, value) so they can be segregated by type
        for nm, sv in scores_by_trace.get(tid, []):
            a["scores"].append((nm, sv))
    # finalize
    eval_scores_by_skill = eval_scores_by_skill or {}
    out = {}
    for skill, a in agg.items():
        cnt = a["count"]
        eval_in_window = [(nm, v) for (ts, nm, v) in eval_scores_by_skill.get(skill, []) if lo <= ts < hi]
        named_scores = a["scores"] + eval_in_window          # [(name, value), ...]
        mean_score, n_scores, score_kind = _preferred_mean(named_scores)
        out[skill] = {
            "count": cnt,
            "error_rate": (a["exec_failed"] / a["exec_total"]) if a["exec_total"] else 0.0,
            "exec_total": a["exec_total"],
            "exec_failed": a["exec_failed"],
            "p50_latency": _pct(a["latencies"], 50),
            "p95_latency": _pct(a["latencies"], 95),
            "cost": round(a["cost"], 6),
            "tokens": a["tokens"],
            "mean_score": mean_score,       # primary (preferred type) - kept for compat
            "n_scores": n_scores,
            "score_kind": score_kind,
            "scores_by_kind": _means_by_kind(named_scores),   # per-type, for the split columns
            "exemplar_trace": a["exemplar_error"] or a["exemplar_cost"],
        }
    return out


def _parse_ts(s):
    if not s:
        return None
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None
    # A naive timestamp (no Z/offset) is read as UTC, NOT shifted by the host's local
    # offset. astimezone() on a naive value would assume machine-local time and move a
    # trace/score into the wrong week-over-week window on a non-UTC host.
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _flag_regressions(this_m, last_m):
    """Compare this vs last per skill, return regression flags + severity."""
    rows = []
    # (unattributed) is not a skill - it holds ordinary tool activity with no skill_name.
    # Keep it in the totals (see main), but never rank it as a regressing skill.
    skills = sorted((set(this_m) | set(last_m)) - {UNATTRIBUTED})
    for skill in skills:
        cur = this_m.get(skill, {})
        prev = last_m.get(skill, {})
        flags = []
        # error rate up (percentage points)
        er_now, er_prev = cur.get("error_rate", 0.0), prev.get("error_rate", 0.0)
        if cur.get("exec_total") and prev.get("exec_total") and (er_now - er_prev) >= ERR_RATE_UP_PP:
            flags.append(f"error rate +{(er_now - er_prev) * 100:.0f}pp ({er_prev * 100:.0f}%→{er_now * 100:.0f}%)")
        # score down (absolute), PER score type, so a graded tessl review drop and a
        # promptfoo pass-rate drop are flagged separately (they are distinct columns)
        cur_k, prev_k = cur.get("scores_by_kind") or {}, prev.get("scores_by_kind") or {}
        for kind in sorted(set(cur_k) | set(prev_k)):
            sn = (cur_k.get(kind) or {}).get("mean")
            sp = (prev_k.get(kind) or {}).get("mean")
            if sn is not None and sp is not None and (sp - sn) >= SCORE_DOWN:
                lbl = SCORE_LABEL.get(kind, kind)
                flags.append(f"{lbl} -{sp - sn:.2f} ({sp:.2f}→{sn:.2f})")
        # cost up (percent)
        c_now, c_prev = cur.get("cost", 0.0), prev.get("cost", 0.0)
        if c_prev > 0 and (c_now - c_prev) / c_prev >= COST_UP_PCT:
            flags.append(f"cost +{(c_now - c_prev) / c_prev * 100:.0f}% (${c_prev:.4f}→${c_now:.4f})")
        # p95 latency up (percent)
        l_now, l_prev = cur.get("p95_latency"), prev.get("p95_latency")
        if l_now is not None and l_prev and (l_now - l_prev) / l_prev >= LAT_UP_PCT:
            flags.append(f"p95 latency +{(l_now - l_prev) / l_prev * 100:.0f}% ({l_prev:.1f}s→{l_now:.1f}s)")
        # severity: CRITICAL 2+ flags, HIGH 1 flag, OK none; NEW/GONE noted separately
        if not cur.get("count"):
            severity = "GONE"
        elif not prev.get("count"):
            severity = "NEW"
        elif len(flags) >= 2:
            severity = "CRITICAL"
        elif len(flags) == 1:
            severity = "HIGH"
        else:
            severity = "OK"
        rows.append({
            "skill": skill, "severity": severity, "flags": flags,
            "this": cur, "last": prev,
        })
    # order: CRITICAL, HIGH, NEW, OK, GONE; then by this-week cost desc
    order = {"CRITICAL": 0, "HIGH": 1, "NEW": 2, "OK": 3, "GONE": 4}
    rows.sort(key=lambda r: (order.get(r["severity"], 9), -(r["this"].get("cost") or 0.0)))
    return rows


def _sev_emoji(sev):
    return {"CRITICAL": "🔴", "HIGH": "🟠", "NEW": "🆕", "OK": "🟢", "GONE": "⚪"}.get(sev, "•")


def _fmt_metric(cur, prev, key, kind):
    c, p = cur.get(key), prev.get(key)
    def f(v):
        if v is None:
            return "-"
        if kind == "cost":
            return f"${v:.4f}"
        if kind == "lat":
            return f"{v:.1f}s"
        if kind == "pct":
            return f"{v * 100:.0f}%"
        if kind == "score":
            return f"{v:.2f}"
        return str(v)
    return f"{f(p)} → {f(c)}"


def render_markdown(doc):
    """Pinned markdown report. Deterministic: same JSON in → same markdown out."""
    L = []
    g = doc.get("generated_at", "")[:16].replace("T", " ")
    tw, lw = doc["this_window"], doc["last_window"]
    L.append(f"# Skill trace-review - week over week ({doc['window_days']}d rolling)")
    L.append("")
    L.append(f"**Generated:** {g} UTC · **Source:** Langfuse `{doc['host']}` · project `{doc['project_id']}`  ")
    L.append(f"**This week:** {tw['from'][:10]} → {tw['to'][:10]} · **Last week:** {lw['from'][:10]} → {lw['to'][:10]}")
    L.append("")
    t = doc["totals"]
    eval_note = f", {t['traces_excluded_as_eval']} eval" if t.get("traces_excluded_as_eval") else ""
    score_note = f"{t['scores']} scores"
    if t.get("eval_scores"):
        score_note += f" ({t['eval_scores']} from eval runs)"
    L.append(f"**Scope:** {t['traces_kept']} traces ({t['traces_excluded_as_noise']} excluded as analysis-noise{eval_note}), "
             f"{t['observations']} observations, {score_note}.")
    at = doc.get("attribution") or {}
    if at.get("total"):
        bs = at.get("by_source") or {}
        parts = [f"{lbl} {bs[k]}" for k, lbl in
                 (("skill_name", "skill_name"), ("slash_command", "slash"), ("hook_sidecar", "hook"))
                 if bs.get(k)]
        breakdown = f" ({', '.join(parts)})" if parts else ""
        L.append(f"**Attribution:** {at.get('attributed', 0)}/{at['total']} traces mapped to a skill{breakdown}.")
    un = doc.get("unattributed") or {}
    if un.get("count"):
        L.append(f"_{un['count']} trace(s) matched no attribution rung (ordinary tool activity, no skill "
                 f"marker), totalling ${un.get('cost', 0.0):.4f}. Not shown per-skill. Coverage grows once the "
                 "skill-activation hook (`devflow init`) starts stamping every session._")
    if not doc.get("has_last_week"):
        L.append("")
        L.append("> ⚠️ **No last-week baseline** in range - every skill below is shown as `🆕 NEW`. "
                 "Week-over-week regression flags activate once a prior week of traces exists.")
    if not doc.get("has_scores"):
        L.append("> ℹ️ **No scores** in range - score-trend column shows `-`. "
                 "Seed scores via `eval/lib/langfuse-push.sh` or Langfuse UI annotations.")
    L.append("")
    rows = doc.get("rows", [])
    regressions = [r for r in rows if r["severity"] in ("CRITICAL", "HIGH")]
    if regressions:
        L.append(f"## ⚠️ {len(regressions)} regression(s) flagged")
        for r in regressions:
            L.append(f"- {_sev_emoji(r['severity'])} **{r['skill']}** - " + "; ".join(r["flags"]))
        L.append("")
    L.append("## Per-skill")
    L.append("")
    L.append("| Sev | Skill | Runs (last→this) | Error rate | p50/p95 latency | Cost | Review (tessl) | Pass-rate | Exemplar |")
    L.append("|-----|-------|------------------|-----------|-----------------|------|---------------|-----------|----------|")

    def _kind_cell(cur, prev, kind, pct=False):
        # last→this for one score type, from each window's scores_by_kind
        def f(m):
            if m is None:
                return "-"
            return f"{m * 100:.0f}%" if pct else f"{m:.2f}"
        cm = (cur.get("scores_by_kind") or {}).get(kind, {}).get("mean")
        pm = (prev.get("scores_by_kind") or {}).get(kind, {}).get("mean")
        return f"{f(pm)} → {f(cm)}"

    for r in rows:
        cur, prev = r["this"], r["last"]
        runs = f"{prev.get('count', 0)} → {cur.get('count', 0)}"
        er = _fmt_metric(cur, prev, "error_rate", "pct")
        def _lat(v):
            return f"{v:.1f}s" if isinstance(v, (int, float)) else "-"
        lat = f"{_lat(cur.get('p50_latency'))} / {_lat(cur.get('p95_latency'))}"
        cost = _fmt_metric(cur, prev, "cost", "cost")
        review = _kind_cell(cur, prev, "tessl_review")     # graded quality (0..1)
        passrate = _kind_cell(cur, prev, "assert_pass", pct=True)  # promptfoo pass-rate
        ex = cur.get("exemplar_trace")
        ex_link = f"[trace]({doc['host']}/project/{doc['project_id']}/traces/{ex})" if ex else "-"
        L.append(f"| {_sev_emoji(r['severity'])} {r['severity']} | `{r['skill']}` | {runs} | {er} | {lat} | {cost} | {review} | {passrate} | {ex_link} |")
    L.append("")
    if regressions:
        L.append("## TL;DR")
        L.append(f"{len(regressions)} skill(s) regressed week-over-week. "
                 "Open the exemplar traces, map each failure to a `SKILL.md` gap, gate the fix with the promptfoo eval harness.")
    else:
        L.append("## TL;DR")
        L.append("No week-over-week regressions flagged. "
                 + ("Baseline still building (no prior week yet)." if not doc.get("has_last_week") else "All skills steady."))
    L.append("")
    return "\n".join(L)


def main():
    if "--format" in sys.argv and sys.argv[sys.argv.index("--format") + 1] == "md":
        out_format = "md"
    else:
        out_format = "json"
    host = os.environ.get("LANGFUSE_HOST", "http://localhost:3100").rstrip("/")
    pk = os.environ.get("LANGFUSE_PUBLIC_KEY")
    sk = os.environ.get("LANGFUSE_SECRET_KEY")
    if not pk or not sk:
        _die("LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY not set (source ~/.config/zsh/secrets)")
    auth_b64 = base64.b64encode(f"{pk}:{sk}".encode()).decode()

    # noise filters: exclude this analysis skill's own activations + an optional session
    exclude_skill = os.environ.get("TRACE_REVIEW_EXCLUDE_SKILL", "devflow:trace-review")
    exclude_session = os.environ.get("TRACE_REVIEW_EXCLUDE_SESSION", "")

    # window math - rolling, with optional --now override for reproducible tests
    now_override = os.environ.get("TRACE_REVIEW_NOW")
    now = _parse_ts(now_override) if now_override else datetime.now(timezone.utc)
    this_lo = now - timedelta(days=WINDOW_DAYS)
    last_lo = now - timedelta(days=2 * WINDOW_DAYS)
    last_hi = this_lo

    try:
        traces = _paginate(host, auth_b64, "traces",
                           {"fromTimestamp": last_lo.isoformat(), "toTimestamp": now.isoformat()})
        observations = _paginate(host, auth_b64, "observations",
                                {"fromStartTime": last_lo.isoformat(), "toStartTime": now.isoformat()})
        scores = _paginate(host, auth_b64, "scores",
                          {"fromTimestamp": last_lo.isoformat(), "toTimestamp": now.isoformat()})
    except urllib.error.URLError as e:
        _die(f"Langfuse unreachable at {host}: {e}")
    except Exception as e:
        _die(f"Langfuse API error: {e}")

    # index
    obs_by_trace = {}
    for o in observations:
        obs_by_trace.setdefault(o.get("traceId"), []).append(o)
    sidecar_path = os.environ.get("TRACE_REVIEW_SIDECAR",
                                  os.path.join(os.path.expanduser("~"), ".devflow", "skill-activations.jsonl"))
    sidecar = _load_sidecar(sidecar_path)
    trace_skill, attr_sources = _attribute_traces(traces, obs_by_trace, sidecar)
    scores_by_trace = {}
    for s in scores:
        v = s.get("value")
        if isinstance(v, (int, float)):
            # keep the score NAME so different types are not averaged together downstream
            scores_by_trace.setdefault(s.get("traceId"), []).append((s.get("name") or "score", float(v)))

    # eval traces (promptfoo/tessl quality runs) carry per-skill-version scores that
    # cannot join to a production trace id; key them by skill + timestamp, and hold the
    # eval traces themselves OUT of the production aggregation below.
    eval_scores_by_skill, eval_ids = _build_eval_scores(traces, scores_by_trace)

    # apply noise filters
    kept = []
    excluded = 0
    eval_excluded = 0
    for t in traces:
        tid = t.get("id")
        if tid is None:
            continue
        if tid in eval_ids:
            eval_excluded += 1; continue
        if trace_skill.get(tid) == exclude_skill:
            excluded += 1; continue
        if exclude_session and t.get("sessionId") == exclude_session:
            excluded += 1; continue
        kept.append(t)

    this_m = _aggregate(kept, obs_by_trace, trace_skill, scores_by_trace, this_lo, now, eval_scores_by_skill)
    last_m = _aggregate(kept, obs_by_trace, trace_skill, scores_by_trace, last_lo, last_hi, eval_scores_by_skill)
    rows = _flag_regressions(this_m, last_m)

    # (unattributed) is reported as a footnote, not ranked as a skill (see _flag_regressions).
    un_this, un_last = this_m.get(UNATTRIBUTED, {}), last_m.get(UNATTRIBUTED, {})
    unattributed = {
        "count": un_this.get("count", 0) + un_last.get("count", 0),
        "cost": round(un_this.get("cost", 0.0) + un_last.get("cost", 0.0), 6),
    }

    total_scores = sum(len(v) for v in scores_by_trace.values())
    eval_score_count = sum(len(v) for v in eval_scores_by_skill.values())
    project_id = (traces[0].get("projectId") if traces else None) or "default"

    # attribution breakdown over KEPT traces (what the report actually ranks): how many
    # traces got a skill, and via which rung. Makes thin coverage visible, not hidden.
    kept_ids = {t.get("id") for t in kept}
    by_source = Counter(src for tid, src in attr_sources.items() if tid in kept_ids)
    attribution = {
        "attributed": sum(1 for tid in trace_skill if tid in kept_ids),
        "total": len(kept),
        "by_source": dict(by_source),
    }

    doc = {
        "generated_at": now.isoformat(),
        "host": host,
        "project_id": project_id,
        "window_days": WINDOW_DAYS,
        "this_window": {"from": this_lo.isoformat(), "to": now.isoformat()},
        "last_window": {"from": last_lo.isoformat(), "to": last_hi.isoformat()},
        "thresholds": {
            "error_rate_up_pp": ERR_RATE_UP_PP * 100,
            "score_down": SCORE_DOWN,
            "cost_up_pct": COST_UP_PCT * 100,
            "lat_up_pct": LAT_UP_PCT * 100,
        },
        "totals": {
            "traces_in_range": len(traces),
            "traces_kept": len(kept),
            "traces_excluded_as_noise": excluded,
            "traces_excluded_as_eval": eval_excluded,
            "observations": len(observations),
            "scores": total_scores,
            "eval_scores": eval_score_count,
            "skills_attributed": sorted([s for s in trace_skill.values()]) and sorted(set(trace_skill.values())),
        },
        "has_last_week": any(m.get("count") for k, m in last_m.items() if k != UNATTRIBUTED),
        # scores that actually feed a ranked skill (production-trace joins + eval scores),
        # not just scores present in the store (eval scores on skills with no prod traces
        # never surface, so store-count would overstate).
        "has_scores": any((r["this"].get("n_scores") or r["last"].get("n_scores")) for r in rows),
        "attribution": attribution,
        "unattributed": unattributed,
        "rows": rows,
    }
    if out_format == "md":
        print(render_markdown(doc))
    else:
        print(json.dumps(doc, indent=2))


if __name__ == "__main__":
    main()
