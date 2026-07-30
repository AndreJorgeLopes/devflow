# Deferred verification — checks that only prove out on live / accumulated data

Some trace-review behaviours cannot be demonstrated the moment they are written: they
need a prior week of traces, two weeks of scores, or real Claude Code sessions produced
*after* a hook is installed. This file is the standing list so those checks are actually
run when the data exists, instead of being silently assumed to work.

**Rule:** every item here must carry (a) a stub-data test that proves the *mechanism*
now, and (b) a concrete live check + trigger for when real data has accrued. If a stub
test is impossible, say why. When a live check passes, move the item to "Verified" with
the date + evidence.

## How to fake the data instead of waiting

Most of these are testable *today* with synthetic data — prefer this over waiting:

- **Windowed regression math**: `TRACE_REVIEW_NOW=<iso>` pins "now", and the bats suite
  feeds synthetic `this_m` / `last_m` (or two-window traces + eval scores) straight into
  `_aggregate` / `_flag_regressions`. This proves score-down / cost-up / error-up / p95
  flags fire, without waiting a real week. See `tests/unit/trace-review.bats`.
- **Score column**: push a stub score for a skill that has a trace in-window
  (`eval/lib/tessl-push.sh <skill> <score>`), then run trace-review with a window wide
  enough to include both. Proves display + join.
- **Two-week score-down**: push a HIGH score dated ~10d ago and a LOW score dated now for
  the same skill, run with `--window 7`; last-week mean = high, this-week = low -> the
  score-down flag fires. Fully fakeable; no real waiting.

## Open (mechanism proven by stub; live demonstration pending)

> **2026-07-30 verification pass (live data checked).** Langfuse `devflow-skills`: 81 traces,
> 3/81 attributed (skill_name 2, slash 1), and only 2 scores (both `trace-review` tessl_review
> dated 2026-07-06). Sidecar `~/.devflow/skill-activations.jsonl`: 113 rows / 59 sessions / 24
> days, but only 3 of those sessions join a Langfuse trace `sessionId`. Two INFRA faults were
> found and fixed this pass: `langfuse-web` showed perpetually "unhealthy" (healthcheck probed
> `localhost:3000` but the app binds the container IP; fixed to `$(hostname -i)`), and a
> redundant bundled-hindsight container was crash-looping (native daemon owns :8888; orphan
> removed). The score-push path was then re-verified end to end (a `tessl-push` landed in
> ClickHouse in ~5s). Net: the accrual items below are still blocked on real *volume*, not on
> a broken pipeline. `0 scores since 07-06` = no create/optimize-skill reviews ran (+ web
> degraded for part of the window), not a dropped-push bug.

- [ ] **Score-DOWN flag on real accumulated data.** Stub: bats
  `_flag_regressions` + the two-window eval-score test. Live: once >=2 weeks of pushed
  scores exist for a skill, confirm a real quality drop shows `🟠/🔴 score -X`.
  Trigger: after the auto-feeder has run for 2+ weeks.
- [ ] **Cost / error-rate / p95 regression flags firing on real week-over-week.** Stub:
  bats threshold tests. Live: confirm a real skill that got slower/pricier is flagged.
  Trigger: first week where a skill's real metrics cross a threshold.
- [ ] **Rung-3 sidecar coverage growing.** Join key verified (CC hook `session_id` ==
  Langfuse trace `sessionId`). Live: re-run `devflow trace-review` a week after the hook
  is installed and confirm `hook` appears in the Attribution breakdown and coverage rises
  above the retroactive 3/57. Trigger: 1 week of real sessions after `devflow init`
  installs the PreToolUse:Skill hook AND telemetry env is on.
- [x] **Enrichment hook writing rows in real sessions.** — VERIFIED (see Verified below).
  The `session_id`-matches-a-trace half is tracked under "Rung-3 sidecar coverage" (only 3/59
  join today; needs sessions with telemetry + hook both on).
- [ ] **Auto-feeder populating the score column unattended.** Stub: manual `tessl-push`
  e2e proved display. Live: confirm that after a skill review runs (create-skill /
  optimize-skill / pre-PR gate), the score lands without a manual push. Trigger: first
  real skill-review after the feeder is wired.

## Verified

- [x] **Enrichment hook writing rows in real sessions** — 2026-07-30. `~/.devflow/skill-activations.jsonl`
  has 113 rows / 59 distinct sessions spanning 2026-07-06 → 2026-07-30, each a valid
  `{session_id, ts, skill}` (e.g. `devflow:resolve-repo`, `superpowers:executing-plans`). The hook
  fires on real skill runs post-install. (The downstream `session_id` → trace `sessionId` join is a
  separate accrual item, "Rung-3 sidecar coverage".)
- [x] **Score-push path lands a score end to end** — 2026-07-30. `eval/lib/tessl-push.sh trace-review 88`
  ingested and appeared in Langfuse (scores 2 → 3) within ~5s, after fixing the `langfuse-web`
  healthcheck. Confirms the auto-feeder → Langfuse → ClickHouse pipe works; the score *column*
  filling unattended still needs a real create/optimize-skill review to run (accrual item above).
