---
description: Extends superpowers:writing-plans with devflow's phase-handoff at the end.
---

This skill extends `superpowers:writing-plans`. Follow the superpowers skill completely.
When the following events occur, apply these additions:

## Before: First action of the skill

1. Detect ticket ID from current branch name (regex `[A-Z]+-[0-9]+`); if none, use `none`.
2. Call `mark_chapter` with `{title: "Plan — <TICKET>", summary: "Writing implementation plan"}`.
   If `mark_chapter` is unavailable (e.g. running outside Claude Code), skip silently.
3. Echo ANSI terminal-title escape:
   ```bash
   printf '\e]2;%s — Plan\007' "<TICKET>"
   ```

## After: Plan saved to disk

Invoke `devflow:phase-handoff` with arguments `--phase plan --next-phase lock-tests`.
The phase-handoff skill writes the frozen-state file, runs a one-click `AskUserQuestion`
gate, and emits a copy-pasteable resume prompt for the user to paste after `/clear`.
Do NOT auto-invoke `devflow:lock-tests` from here — the next phase must start in a clean
context after `/clear`.

$ARGUMENTS
