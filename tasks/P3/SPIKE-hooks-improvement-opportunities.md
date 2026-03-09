---
id: SPIKE-hooks-improvement-opportunities
title: "Research Opportunities to Improve Devflow Flows Using Hooks"
priority: P3
category: spikes
status: in-progress
depends_on: []
estimated_effort: M
files_to_touch:
  - devflow-plugin/hooks/hooks.json
  - skills/**/*.md
---

# Research Opportunities to Improve Devflow Flows Using Hooks

## Context

Claude Code hooks (PreToolUse, PostToolUse, Stop, SessionStart, Notification, etc.) are pragmatic triggers that execute shell commands in response to agent lifecycle events. Currently, devflow only uses a single `Stop` hook (a reminder to run visualizations/session-summary). There are likely many opportunities to automate skill invocations, quality checks, and task lifecycle management via hooks.

## Research Questions

1. **Task lifecycle hooks**: Can we use hooks to auto-detect when a task is being worked on and auto-update its status? For example:
   - `SessionStart` → detect task from branch/session name → mark as `in-progress`
   - `Stop` → prompt to mark task as `done` if it looks complete
   - **Partially addressed:** Stop hook now prompts finish-feature flow (see `lib/hooks/stop-finish-prompt.sh`)

2. **Pre-push quality gates**: Can a `PreToolUse` hook on `git push` automatically trigger `pre-push-check` or at least warn if checks haven't been run?

3. **Memory hygiene**: Can a `Stop` hook auto-trigger `reflect-session` or `retain-learning` when significant work was done?

4. **Visualization freshness**: Can hooks detect when architecture-relevant files change and auto-suggest visualization updates?

5. **Commit message quality**: Can a `PreToolUse` hook on `git commit` validate conventional commit format?

6. **Skill auto-invocation**: Can hooks detect patterns (e.g., "starting a new feature", "creating a PR") and auto-invoke the relevant skill if the agent hasn't already?
   - **Partially addressed:** Stop hook suggests `/devflow:finish-feature` when on feature branch with commits

7. **Agent-deck integration**: The global hooks already use `agent-deck hook-handler` — how can devflow plugin hooks complement these without conflicts?

8. **Task completion automation**: When `devflow:finish-feature` or `devflow:create-pr` completes successfully, could a hook auto-invoke `devflow:task-complete`?
   - **Partially addressed:** Stop hook chains to finish-feature which includes task completion in its flow

## Desired Outcome

A prioritized list of hook-based automations with:
- Which hook type to use
- What it triggers
- Estimated complexity
- Whether it belongs in the devflow plugin hooks or global hooks
- Any risks (e.g., hooks that are too aggressive and annoy the developer)

## Progress

### Implemented (2026-03-09): Smart Hooks

Two hooks implemented in `lib/hooks/`, registered via `~/.claude/settings.json` and `devflow init`:

1. **Stop → finish-feature prompt** (`stop-finish-prompt.sh`): Detects feature branch with commits ahead of main, prompts user to run `/devflow:finish-feature` or continue. Uses exit code 2 to block stop and re-activate. Loop prevention via `stop_hook_active` field.

2. **UserPromptSubmit → auto fetch-rebase** (`prompt-fetch-rebase.sh`): On each prompt, fetches origin, compares changed files. Auto-rebases when no overlap. Presents 3-option selector when conflicts detected. Session opt-out via `/tmp/devflow-no-rebase-<session_id>`.

**Also added:** `UserPromptSubmit` hook for proactive rebase — not in the original research questions but emerged as a high-value automation during implementation.

## Acceptance Criteria

- [ ] Audit all available Claude Code hook types and their triggers
- [ ] Map each devflow skill to potential hook triggers
- [x] Identify 3-5 highest-value hook automations
- [x] Create implementation tasks for the top picks
- [ ] Document any hook limitations or gotchas discovered
