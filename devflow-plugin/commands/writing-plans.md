---
description: [0.17.1] Extends superpowers:writing-plans with devflow's phase-handoff at the end.
---

This skill extends `superpowers:writing-plans`. Follow the superpowers skill completely.
When the following events occur, apply these additions:

## Step 0 — Re-establish the feature worktree (do this before anything else)

If this session was spawned by `devflow:phase-handoff`, it was forked into a FRESH throwaway worktree that is NOT on the feature branch (`spawn_task` always forks off the default branch; there is no way to pin it). Move to the real feature worktree before the "Before" steps, using the `devflow handoff context` block in the message that invoked this skill.

1. Parse from that block: `Feature worktree`, `Feature branch`, `Main repo (shared .git)`. If no such block is present (skill invoked manually, not via a handoff), skip Step 0 — you are already in the right place.

2. Ensure the feature worktree exists on the feature branch, then make it your working directory:
   ```bash
   feature_wt="<Feature worktree>"
   feature_branch="<Feature branch>"
   main_repo="<Main repo>"

   git -C "$main_repo" worktree prune   # clear stale registrations (a worktree dir deleted with rm -rf)
   # Validity check, not mere existence: recreate unless we can cd in AND are already on the feature branch.
   # (`[ -d ]` alone would skip recovery for a stale non-worktree dir or a detached/wrong-branch checkout.)
   if ! ( cd "$feature_wt" 2>/dev/null && [ "$(git branch --show-current 2>/dev/null)" = "$feature_branch" ] ); then
     git -C "$main_repo" worktree add "$feature_wt" "$feature_branch" 2>/dev/null || {
       # path occupied, or branch already checked out elsewhere — reuse that existing checkout.
       # Strip the leading `worktree ` token (not awk $2) so worktree paths containing spaces survive.
       existing="$(git -C "$main_repo" worktree list --porcelain | awk -v b="refs/heads/$feature_branch" '
         /^worktree /{ $1=""; sub(/^ /,""); w=$0 } /^branch /{ if ($2==b) print w }')"
       [ -n "$existing" ] && feature_wt="$existing"
     }
   fi
   cd "$feature_wt"

   on="$(git branch --show-current)"
   [ "$on" = "$feature_branch" ] || { echo "WORKTREE RECOVERY FAILED: in '$on', expected '$feature_branch' at $feature_wt"; exit 1; }
   ```

3. Every later step — reading the spec/plan artefacts, writing the plan, `git` commits, the terminal `phase-handoff` — runs in `$feature_wt`. The Read/Edit tools need an ABSOLUTE path: open each artefact as `$feature_wt/<relative-path-from-the-block>`. If the worktree could not be recreated, read any committed artefact with `git -C "$main_repo" show "$feature_branch:<rel-path>"`. Never write into the throwaway spawn worktree — it is an orphan the user prunes separately.

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
