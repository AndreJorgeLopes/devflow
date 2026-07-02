#!/usr/bin/env python3
"""devflow trace-review engine - per-skill week-over-week Langfuse regression analysis.

READ-ONLY. Pulls traces/observations/scores from a self-hosted Langfuse, attributes
each trace to a skill (via the skill_name attribute Claude Code emits on
claude_code.tool spans), compares a rolling "this week" vs "last week"
window, flags regressions against balanced thresholds, and emits a JSON document.

Why this exists (baseline failure it fixes): a cold agent assumes a `skill.name`
trace field, when the real key is `skill_name` and it lands on `claude_code.tool`
spans (NOT on the child `claude_code.tool.execution` span). The join here scans every
observation on the trace, so it finds skill_name wherever it sits. It also naively sums
cost/latency across mixed span types (interaction wall-clock + llm latency) which
inflates totals. This engine joins by traceId and uses Langfuse's already-aggregated
per-trace `totalCost`/`latency`, so the numbers are correct and reproducible.

Attribution coverage caveat: skill_name is only present when a Claude Code skill was
active, so ordinary tool activity buckets into "(unattributed)". That bucket is kept in
the totals for honesty but held OUT of the per-skill regression ranking (it is not a
skill). Per-skill grouping is therefore only as complete as skill_name is in the traces.

Output: a single JSON object on stdout. The skill renders it to markdown from a
pinned template. No AI judgement in here - pure deterministic aggregation.
"""
import sys, os, json, base64, urllib.request, urllib.parse, urllib.error
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


def _build_trace_skill_map(observations):
    """traceId -> skill_name (first non-null skill_name seen on the trace's spans)."""
    m = {}
    for o in observations:
        tid = o.get("traceId")
        if not tid:
            continue
        sn = _attr(o, "skill_name")
        if sn and tid not in m:
            m[tid] = sn
    return m


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


def _aggregate(traces, obs_by_trace, trace_skill, scores_by_trace, lo, hi):
    """Aggregate per skill for traces whose timestamp is in [lo, hi)."""
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
        for sv in scores_by_trace.get(tid, []):
            a["scores"].append(sv)
    # finalize
    out = {}
    for skill, a in agg.items():
        cnt = a["count"]
        out[skill] = {
            "count": cnt,
            "error_rate": (a["exec_failed"] / a["exec_total"]) if a["exec_total"] else 0.0,
            "exec_total": a["exec_total"],
            "exec_failed": a["exec_failed"],
            "p50_latency": _pct(a["latencies"], 50),
            "p95_latency": _pct(a["latencies"], 95),
            "cost": round(a["cost"], 6),
            "tokens": a["tokens"],
            "mean_score": (sum(a["scores"]) / len(a["scores"])) if a["scores"] else None,
            "n_scores": len(a["scores"]),
            "exemplar_trace": a["exemplar_error"] or a["exemplar_cost"],
        }
    return out


def _parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


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
        # score down (absolute)
        s_now, s_prev = cur.get("mean_score"), prev.get("mean_score")
        if s_now is not None and s_prev is not None and (s_prev - s_now) >= SCORE_DOWN:
            flags.append(f"score -{s_prev - s_now:.2f} ({s_prev:.2f}→{s_now:.2f})")
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
    L.append(f"**Scope:** {t['traces_kept']} traces ({t['traces_excluded_as_noise']} excluded as analysis-noise), "
             f"{t['observations']} observations, {t['scores']} scores.")
    un = doc.get("unattributed") or {}
    if un.get("count"):
        L.append(f"_{un['count']} of these traces carried no `skill_name` (ordinary tool activity), "
                 f"totalling ${un.get('cost', 0.0):.4f}. Not shown per-skill - attribution needs "
                 "`skill_name` on the trace, which Claude Code only stamps when a skill is active._")
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
    L.append("| Sev | Skill | Runs (last→this) | Error rate | p50/p95 latency | Cost | Mean score | Exemplar |")
    L.append("|-----|-------|------------------|-----------|-----------------|------|-----------|----------|")
    for r in rows:
        cur, prev = r["this"], r["last"]
        runs = f"{prev.get('count', 0)} → {cur.get('count', 0)}"
        er = _fmt_metric(cur, prev, "error_rate", "pct")
        def _lat(v):
            return f"{v:.1f}s" if isinstance(v, (int, float)) else "-"
        lat = f"{_lat(cur.get('p50_latency'))} / {_lat(cur.get('p95_latency'))}"
        cost = _fmt_metric(cur, prev, "cost", "cost")
        sc = _fmt_metric(cur, prev, "mean_score", "score")
        ex = cur.get("exemplar_trace")
        ex_link = f"[trace]({doc['host']}/project/{doc['project_id']}/traces/{ex})" if ex else "-"
        L.append(f"| {_sev_emoji(r['severity'])} {r['severity']} | `{r['skill']}` | {runs} | {er} | {lat} | {cost} | {sc} | {ex_link} |")
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
    trace_skill = _build_trace_skill_map(observations)
    scores_by_trace = {}
    for s in scores:
        v = s.get("value")
        if isinstance(v, (int, float)):
            scores_by_trace.setdefault(s.get("traceId"), []).append(float(v))

    # apply noise filters
    kept = []
    excluded = 0
    for t in traces:
        tid = t.get("id")
        if tid is None:
            continue
        if trace_skill.get(tid) == exclude_skill:
            excluded += 1; continue
        if exclude_session and t.get("sessionId") == exclude_session:
            excluded += 1; continue
        kept.append(t)

    this_m = _aggregate(kept, obs_by_trace, trace_skill, scores_by_trace, this_lo, now)
    last_m = _aggregate(kept, obs_by_trace, trace_skill, scores_by_trace, last_lo, last_hi)
    rows = _flag_regressions(this_m, last_m)

    # (unattributed) is reported as a footnote, not ranked as a skill (see _flag_regressions).
    un_this, un_last = this_m.get(UNATTRIBUTED, {}), last_m.get(UNATTRIBUTED, {})
    unattributed = {
        "count": un_this.get("count", 0) + un_last.get("count", 0),
        "cost": round(un_this.get("cost", 0.0) + un_last.get("cost", 0.0), 6),
    }

    total_scores = sum(len(v) for v in scores_by_trace.values())
    project_id = (traces[0].get("projectId") if traces else None) or "default"

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
            "observations": len(observations),
            "scores": total_scores,
            "skills_attributed": sorted([s for s in trace_skill.values()]) and sorted(set(trace_skill.values())),
        },
        "has_last_week": any(m.get("count") for k, m in last_m.items() if k != UNATTRIBUTED),
        "has_scores": total_scores > 0,
        "unattributed": unattributed,
        "rows": rows,
    }
    if out_format == "md":
        print(render_markdown(doc))
    else:
        print(json.dumps(doc, indent=2))


if __name__ == "__main__":
    main()
