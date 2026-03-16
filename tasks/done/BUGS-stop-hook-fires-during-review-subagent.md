---
id: BUGS-stop-hook-fires-during-review-subagent
title: "Stop hook (finish-feature prompt) fires incorrectly during devflow review subagent"
priority: P0
category: bugs
status: done
depends_on: []
estimated_effort: S
files_to_touch:
  - lib/hooks/stop-finish-prompt.sh
  - bin/devflow
---

## Problem

When running `devflow review <MR_URL>`, the spawned Claude Code subagent triggers
the Stop hook (`stop-finish-prompt.sh`) upon completion. The hook detects unmerged
work on a feature branch and prompts for `/devflow:finish-feature`, which is
completely irrelevant for a review-only subagent.

### Reproduction

```bash
# On a feature branch with commits ahead of main and no MR yet
devflow review https://gitlab.com/aircall/core/messaging/-/merge_requests/1991
```

The review completes but the subagent gets blocked by the stop hook prompting
finish-feature flow.

## Root Cause

The stop hook has no awareness of **why** the agent session is running. It blindly
checks "feature branch + commits ahead + no PR" and blocks stop. When `devflow review`
spawns a Claude Code subagent via `claude --print`, that subagent inherits the
working directory context (feature branch) and the stop hook fires on it.

## Options

### Option A: Pass `--hooks=false` flag on review subagent invocation

`devflow review` already spawns Claude Code with `--print`. Adding a flag to
disable hooks for the subagent prevents the stop hook from firing in review context.

**Pros:** Simple, targeted fix.
**Cons:** Disables ALL hooks for the review subagent (may miss useful ones in future).

### Option B: Environment variable escape hatch in the stop hook

Set `DEVFLOW_NO_STOP_HOOK=1` before invoking the review subagent. The stop hook
checks for this env var and exits 0 immediately.

**Pros:** Surgical — only disables this specific hook. Other hooks still run.
**Cons:** Env var coupling between bin/devflow and the hook script.

### Option C: Move finish-feature out of the stop hook entirely

Replace the stop hook with a different mechanism (e.g., a PostToolUse hook on the
last tool call, or a UserPromptSubmit reminder). The stop hook is inherently
problematic because it fires on ALL agent session endings, including subagents.

**Pros:** Eliminates the class of problems entirely.
**Cons:** Higher effort, needs a viable alternative trigger.

## Recommended Fix

Start with **Option B** (env var escape hatch) as an immediate fix, while
evaluating **Option C** as a longer-term architectural improvement via the
SPIKE-hooks-improvement-opportunities task.

## Verification

- Run `devflow review <MR_URL>` on a feature branch — should complete without
  finish-feature prompt
- Run normal `claude` session on a feature branch, then stop — should still
  prompt finish-feature as before
