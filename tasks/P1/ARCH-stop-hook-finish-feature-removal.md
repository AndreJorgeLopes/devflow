---
id: ARCH-stop-hook-finish-feature-removal
title: "Remove finish-feature prompting from stop hook — replace with skill-level flow control"
priority: P1
category: architecture
status: done
depends_on: []
estimated_effort: M
files_to_touch:
  - lib/hooks/stop-finish-prompt.sh
  - devflow-plugin/commands/new-feature.md
  - devflow-plugin/commands/finish-feature.md
  - bin/devflow
  - CLAUDE.md
---

## Problem

The stop hook (`stop-finish-prompt.sh`) is fundamentally flawed as a mechanism for
prompting finish-feature because:

1. **Fires on ALL agent stops** — including subagents spawned by `devflow review`,
   refactor flows, agent-deck sessions, etc.
2. **Shows "Stop hook error:" in UI** — hardcoded by Claude Code, cannot be suppressed.
3. **PR/MR detection is fragile** — fails when the reviewed MR is for a different branch
   than the current one, or when `gh`/`glab` CLI has auth issues.
4. **Requires per-subagent escape hatches** — each new subagent type would need its own
   env var (`DEVFLOW_REVIEW_SUBAGENT`, etc.) to bypass the hook.
5. **Session-wide blast radius** — the hook pollutes every stop event for the entire
   session, even when finish-feature isn't relevant.

## Design: Skill-Level Flow Control

Replace the stop hook with **skill-level instructions** that scope the finish-feature
transition to the sessions where it's actually relevant.

### Primary mechanism: new-feature skill
The `new-feature.md` skill already manages the full lifecycle (setup → brainstorm →
implement → finish). Add an explicit instruction that the session MUST conclude with
`finish-feature` after implementation is complete. This is scoped to the session
where new-feature was invoked — subagents don't inherit it.

### Secondary mechanism: finish-feature skill instruction
The existing "CRITICAL: Do NOT stop after PR creation" instruction (line 167) stays.

### Tertiary mechanism: CLAUDE.md convention
For ad-hoc feature work (user doesn't invoke new-feature), add a convention to the
project CLAUDE.md about the expected feature lifecycle.

### Keep PostToolUse hook
`post-pr-continue.sh` stays as-is — it handles the specific "continue steps 7-9 after
PR creation" case and doesn't have the session-wide blast radius problem.

## Implementation

### Task 1: Gut the stop hook
- Remove all finish-feature logic from `stop-finish-prompt.sh`
- Make it exit 0 immediately (keep file as stub for future stop-hook needs)
- Remove the `DEVFLOW_REVIEW_SUBAGENT` env var escape hatch from both
  `stop-finish-prompt.sh` and `bin/devflow` (no longer needed)

### Task 2: Add finish-feature transition to new-feature.md
- Add a visible instruction in the "Important" section that after implementation,
  the agent MUST invoke `devflow:finish-feature`
- This replaces the stop hook's "reminder to run finish-feature" function

### Task 3: Update CLAUDE.md with feature lifecycle convention
- Add a convention in the Hooks Architecture section about the expected lifecycle:
  new-feature → implement → finish-feature (all in one session)

### Task 4: Clean up related artifacts
- Remove `BUGS-stop-hook-fires-during-review-subagent.md` (superseded by this task)
- Update `SPIKE-hooks-improvement-opportunities.md` to note the stop hook was removed

## Verification

- `devflow review <MR_URL>` on a feature branch completes without finish-feature prompt
- Normal interactive session on a feature branch stops cleanly (no hook blocking)
- Subagents stop without interference
- `new-feature` flow still naturally transitions to `finish-feature`
