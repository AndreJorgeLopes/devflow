---
description: Extends superpowers:writing-plans with agent-deck parallel session handoff for devflow workflows.
---

This skill extends `superpowers:writing-plans`. Follow the superpowers skill completely.
When the following events occur, apply these additions:

## After: Plan execution handoff — Parallel Session chosen

When the user chooses the "Parallel Session" execution option, apply these steps
**in addition to** what superpowers provides:

### Manual command (always show first)

Print the manual command the user can run in a new terminal (same worktree directory):

    To continue manually in a new terminal, run:

      cd <current-worktree-path>
      claude --resume no -p "Read the plan at docs/plans/<plan-filename>.md and use superpowers:executing-plans to implement it task-by-task."

### Agent-deck auto-launch (offer after manual command)

Ask: **"Want me to launch this automatically via agent-deck?"**

If yes:

1. Run `agent-deck group list --json` and parse the JSON output
2. Collect all groups and subgroups, **filtering out** any named `DONE` or `done` (case-insensitive)
3. Present the filtered list with a numbered menu, plus **"No group (root level)"**
4. **CRITICAL: Use the exact group `path` from the JSON output** (e.g., `devflow`, not `Devflow`). The non-JSON display capitalizes names, but group names are case-sensitive. Using the wrong case creates a duplicate group.
5. Determine the session title: prefer the **ticket/feature ID** from the branch name (e.g., `MES-1234` from `feat/MES-1234-some-feature`) or the branch name itself. Append ` — Implementation` as suffix.
6. After the user picks a group (or root), run:

    agent-deck launch <current-worktree-path> \
      --no-parent \
      --no-wait \
      -t "<ticket-or-branch> — Implementation" \
      -g "<chosen-group-path-from-json>" \
      -m "Read the plan at docs/plans/<plan-filename>.md and use superpowers:executing-plans to implement it task-by-task."

   If "No group" was chosen, omit `-g` entirely.

   **CRITICAL flag reference:**
   - `-m` or `--message` = initial prompt to send (**NOT `-p`**, which is "parent session")
   - `-t` = session title
   - `-c` = tool/command to run (e.g., `claude`)
   - `-g` = assign to a group
   - `--no-parent` = don't link to a parent session
   - `--no-wait` = don't block waiting for agent readiness (avoids timeout errors)
   - Do **NOT** use `--worktree` if the worktree already exists — pass the path as the positional argument

7. **IMPORTANT:** Use the current worktree path as the positional argument — do NOT use `--worktree`, as the worktree already exists.
8. Confirm the session was created and tell the user to check it via agent-deck TUI or `agent-deck session attach "<session-id>"`.

   **Note:** `agent-deck list` lists all sessions. `agent-deck group list` lists all groups. Neither supports a `-g` flag for filtering — they already show everything.
