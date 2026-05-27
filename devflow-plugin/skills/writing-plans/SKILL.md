---
name: writing-plans
description: Extends superpowers:writing-plans with devflow's phase-handoff at the end.
---

This skill extends `superpowers:writing-plans`. Follow the superpowers skill completely.
When the following events occur, apply these additions:

## Before: First action of the skill

1. Detect ticket ID from current branch name (regex `[A-Z]+-[0-9]+`); if none, use `none`.
2. Call `mark_chapter` with `{title: "Plan — <TICKET>", summary: "Writing implementation plan"}`.
   If `mark_chapter` is unavailable (e.g. running outside Claude Code), skip silently.
3. Set terminal window title (CLI Claude Code only — silent no-op in Claude Desktop):
   ```bash
   [ -t 1 ] && printf '\e]2;%s — Plan\007' "<TICKET>" || true
   ```
   In Claude Desktop there is no controlling terminal — the visible phase signal comes from `mark_chapter` (step 2).

## After: Plan saved to disk

Invoke `devflow:phase-handoff` with arguments `--phase plan --next-phase lock-tests`.
The phase-handoff skill writes the frozen-state file, runs a one-click `AskUserQuestion`
gate, then spawns a new Claude Desktop session via `mcp__ccd_session__spawn_task` titled
`[<TICKET>] [MR#<N>] Lock Tests` (visible in the sidebar). Do NOT auto-invoke
`devflow:lock-tests` from here — the next phase must start in a fresh spawned session,
not in this one.

$ARGUMENTS
