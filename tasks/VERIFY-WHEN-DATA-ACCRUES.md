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
- [ ] **Enrichment hook writing rows in real sessions.** Stub: bats feeds a synthetic
  PreToolUse payload and asserts the sidecar row. Live: after `devflow init`, invoke any
  skill and confirm a real row lands in `~/.devflow/skill-activations.jsonl` with a
  `session_id` that matches a Langfuse trace `sessionId`. Trigger: first real skill run
  post-install.
- [ ] **Auto-feeder populating the score column unattended.** Stub: manual `tessl-push`
  e2e proved display. Live: confirm that after a skill review runs (create-skill /
  optimize-skill / pre-PR gate), the score lands without a manual push. Trigger: first
  real skill-review after the feeder is wired.

## Verified

(move items here with date + evidence once the live check passes)
