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
The phase-handoff skill writes the frozen-state file and prompts the user to `/compact`
before the next phase begins. Do NOT auto-invoke `superpowers:executing-plans` from here —
implementation must start in a clean context after `/compact`.
