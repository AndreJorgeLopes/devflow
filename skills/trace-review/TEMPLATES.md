# trace-review - report format & extension reference

Loaded on demand. The report shape is produced deterministically by
`lib/trace-review.py` (`--format md`); this file documents it so reviewers and
future maintainers can reason about the contract without reading the engine.

## Report structure (pinned)

```
# Skill trace-review - week over week (Nd rolling)

**Generated:** <UTC> · **Source:** Langfuse `<host>` · project `<id>`
**This week:** <from> → <to> · **Last week:** <from> → <to>

**Scope:** <kept> traces (<excluded> excluded as analysis-noise), <obs> observations, <scores> scores.

> ⚠️ No last-week baseline … (only when has_last_week is false)
> ℹ️ No scores … (only when has_scores is false)

## ⚠️ N regression(s) flagged          (only when CRITICAL/HIGH rows exist)
- 🔴 **<skill>** - <flag>; <flag>

## Per-skill
| Sev | Skill | Runs (last→this) | Error rate | p95 latency | Cost | Mean score | Exemplar |
...one row per skill, ordered CRITICAL→HIGH→NEW→OK→GONE, then cost desc...

## TL;DR
<one-line verdict>
```

## Severity rules

| Severity | Meaning |
|---|---|
| 🔴 CRITICAL | 2+ regression flags this week vs last |
| 🟠 HIGH | exactly 1 regression flag |
| 🆕 NEW | present this week, absent last week (no baseline to compare) |
| 🟢 OK | present both weeks, no flag |
| ⚪ GONE | present last week, absent this week |

## Regression flags (balanced defaults)

| Metric | Flags when | Env override |
|---|---|---|
| error rate | up ≥ 10 percentage points (per tool execution) | `TRACE_REVIEW_ERR_RATE_UP_PP` |
| mean score | down ≥ 0.05 absolute | `TRACE_REVIEW_SCORE_DOWN` |
| cost | up ≥ 25% | `TRACE_REVIEW_COST_UP_PCT` |
| p95 latency | up ≥ 25% | `TRACE_REVIEW_LAT_UP_PCT` |
| window | rolling 7 days | `TRACE_REVIEW_WINDOW_DAYS` |

A flag fires only when **both** weeks have data for that skill (score/error need a
prior value). NEW/GONE skills are surfaced but never error-flagged.

## Data model (why the engine, not hand-rolled queries)

- `skill_name` is emitted on `claude_code.tool.execution` spans (when a Skill tool
  fires). It is **not** a top-level trace field, and is **not** `skill.name`.
- Cost / tokens live on sibling `claude_code.llm_request` spans under the same trace.
- The engine maps `traceId → skill_name`, then attributes each trace's
  Langfuse-computed `totalCost` + `latency` (already aggregated, correct) to that skill.
  Traces with no skill activation fall into `(unattributed)`.
- Scores come from `/api/public/scores`, joined to skills via `traceId`.
- Error rate is per `claude_code.tool.execution` span (failed = `success==false` /
  ERROR level / `error` attr), aggregated over the skill's traces. Permission gates
  (`claude_code.tool.blocked_on_user`, `decision=reject`) are not executions and never
  count as errors.

## Exemplar trace link

`<host>/project/<projectId>/traces/<traceId>` - the engine picks the first errored
trace, else the highest-cost trace, for each skill.

## Scheduler backends (extension seam)

Two independent axes:

1. **Scheduler backend** - `cron` (portable, OS-level) or `claude` (Claude Code cloud
   routine, machine-off, Claude-only). OpenCode has no native scheduler; use `cron`
   (`opencode run`) or the third-party `opencode-scheduler` plugin.
2. **Agent-invoke command** - `lib/utils.sh` `agent_invoke_cmd` resolves the headless
   invocation per `detect_agent_provider` (claude-code → `env CLAUDECODE="" claude
   --print`; opencode → `opencode run`).

**Add a provider** (e.g. Codex) without touching the flow:
1. one arm in `detect_agent_provider` (detect the binary)
2. one arm in `agent_invoke_cmd` (its headless command)
3. if it needs a non-OS scheduler, one backend arm in `_trace_review_schedule`

The cron entry, setup/teardown, and `devflow trace-review run` entrypoint stay unchanged.
