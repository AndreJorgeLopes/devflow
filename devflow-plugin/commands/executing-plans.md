---
description: [0.26.0] Devflow wrapper for the upstream executing-plans skill. Use when you have a written implementation plan to execute task-by-task. ALWAYS invoke `/devflow:executing-plans` rather than the upstream skill directly — this wrapper guarantees that the post-implementation handoff goes to `/devflow:finish-feature` (devflow's verification + PR/MR creation flow) instead of `superpowers:finishing-a-development-branch` (the upstream default, which doesn't integrate with devflow's VCS-coherent finish flow).
---

You are the devflow wrapper for the upstream executing-plans workflow. The wrapper exists for TWO reasons:

1. **Forced finish-feature handoff.** Upstream `executing-plans` natively chains to `superpowers:finishing-a-development-branch` after the last task. Devflow has its own `/devflow:finish-feature` flow that runs verification, creates a PR/MR via devflow's VCS-coherent logic, and retains learnings to Hindsight. This wrapper intercepts the terminal handoff so the devflow finish flow runs instead.
2. **Single canonical entry point.** All devflow callers (`lock-tests.md` Phase 2, `phase-handoff.md`'s impl-phase invocation, the resume prompt in a spawned implementation session) invoke `/devflow:executing-plans` instead of `/executing-plans` or `superpowers:executing-plans`. If the upstream skill is renamed/moved/replaced, only this wrapper updates.

## Step 0 — Re-establish the feature worktree (do this before Phase 0)

This phase is normally reached via `devflow:phase-handoff`, which forks a FRESH throwaway worktree that is NOT on the feature branch (`spawn_task` always forks off the default branch; there is no way to pin it). The implementation phase WRITES production code and commits it, so landing on the wrong branch is especially damaging. Move to the real feature worktree before delegating upstream, using the `devflow handoff context` block in the message that invoked this skill.

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

3. The upstream skill (Phase 1) and every commit it makes run in `$feature_wt`. Pass the handoff context through to it. The Read/Edit tools need an ABSOLUTE path: open each artefact as `$feature_wt/<relative-path-from-the-block>` (fallback if the worktree could not be recreated: `git -C "$main_repo" show "$feature_branch:<rel-path>"`). Never write into the throwaway spawn worktree — it is an orphan the user prunes separately.

## Phase 0 — Locate the upstream skill

1. Try invoking `superpowers:executing-plans` via the Skill tool. If it loads, proceed to Phase 1.

2. **If the upstream skill is missing**, search the available-skills list for variants matching `*executing*plans*` or `*implementing*plans*`. If a variant matches (rename case), use it and warn the user inline: `Note: superpowers:executing-plans renamed to <variant>. Update devflow:executing-plans skill body to point at the new name.`

3. **If still missing**, check `~/.devflow/cache/superpowers-changelog.md`:
   - If the file exists AND is < 24h old → read it for skill-rename or removal notes.
   - Else, invoke the `defuddle` skill on `https://github.com/obra/superpowers/blob/main/CHANGELOG.md` and write the result to `~/.devflow/cache/superpowers-changelog.md`. (If `defuddle` is unavailable, skip this step.)
   - Surface any relevant rename notes to the user.

4. **If all of the above fail**, emit:
   ```
   Upstream `superpowers:executing-plans` skill not found and no cached changelog clue. Either:
   - Verify the superpowers plugin is installed (`claude plugins list | grep superpowers`)
   - Re-run the OMC setup flow to refresh plugins
   - Or fetch the latest superpowers CHANGELOG manually to check if the skill was renamed
   ```
   Then exit. Do NOT reimplement the executing-plans logic inline.

## Phase 1 — Delegate to upstream

Hand off to the located skill. Pass through `$ARGUMENTS` verbatim. Let the upstream skill drive its red-green-refactor loop, per-task review checkpoints, and TodoWrite tracking.

## Phase 2 — Force finish-feature handoff

**CRITICAL OVERRIDE:** When the upstream skill reports completion (status DONE, DONE_WITH_CONCERNS, or its equivalent terminal state), **devflow takes over the finish handoff**.

Do **NOT** invoke `superpowers:finishing-a-development-branch` even if the upstream skill instructs you to. Devflow's finish flow lives in `/devflow:finish-feature` and:

- runs verification (`devflow check`)
- detects the VCS provider (GitHub vs GitLab) and creates a PR/MR with the devflow PR template
- retains session learnings to Hindsight
- defers worktree cleanup to the terminal (not the agent)

Invoke `/devflow:finish-feature` directly. Pass any `BLOCKED` / `NEEDS_CONTEXT` status from the upstream skill into the finish-feature flow so the user is aware of incomplete work before PR creation.

## Important

- This wrapper is the ONLY place where the "intercept finishing-a-development-branch" override lives. If you find that override repeated in another devflow skill, that's drift — remove it and rely on this wrapper.
- The wrapper does NOT skip the upstream skill's per-task discipline (TDD red-green, review checkpoints). It only overrides the FINAL handoff target.
- If the user explicitly asks for `superpowers:finishing-a-development-branch` (or invokes it directly), respect that. The wrapper's override applies only when control returns from the upstream skill via the normal completion path.

$ARGUMENTS
