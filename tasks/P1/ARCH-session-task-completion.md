---
id: ARCH-session-task-completion
title: "Session/Task Completion Command"
priority: P1
category: architecture
status: open
depends_on:
  - ARCH-devflow-work-entry-point
estimated_effort: L
files_to_touch:
  - lib/done.sh
  - bin/devflow
  - skills/process-discipline/done.md
  - skills/registry.json
---

# Session/Task Completion Command

## Context

Devflow has a clear entry point for starting work (`devflow work`) but no corresponding exit point. When a task is finished, the developer currently has to manually: run verification, commit, push, create a PR, retain learnings, close the agent session, and clean up the worktree. This should be streamlined into two complementary pieces:

1. **Agent-side skill** (`done.md`) — the agent runs verification, commits, pushes, creates a PR, and retains learnings
2. **CLI-side command** (`devflow done`) — the developer runs cleanup: merge worktree, delete session, remove temp files

The skill handles everything INSIDE the agent session. The CLI handles everything OUTSIDE (terminal-level cleanup after the session ends).

## Problem Statement

Task completion is fragmented and error-prone:

- Developers forget to run verification before pushing
- Code review checks (`devflow check`) are skipped
- Session learnings aren't retained to Hindsight (knowledge is lost)
- Worktrees accumulate because cleanup is manual
- Agent sessions linger in agent-deck after the work is done
- No summary is logged to Langfuse for observability

## Desired Outcome

A clean, repeatable task completion flow:

1. Agent runs the `done` skill → verification, commit, push, PR, retain learnings
2. Developer runs `devflow done` → merge worktree, close session, cleanup

## Implementation Guide

### Part 1: The Agent-Side Skill (`done.md`)

Create `skills/process-discipline/done.md`:

````markdown
---
name: done
description: "Complete a task: verify, commit, push, create PR, retain learnings"
trigger: "When the user says the task is done, or asks to finish/complete/wrap up"
type: rigid
---

# Task Completion Skill

When the user indicates a task is complete, follow this sequence exactly.
Do NOT skip steps. Do NOT claim completion until all steps pass.

## Step 1: Verification

Run all relevant verification commands. ALL must pass before proceeding.

1. **Tests**: Run the project's test command (e.g., `yarn test`, `npm test`, `pytest`)
   - Only run tests for affected files if the project supports targeted testing
   - If tests fail: fix them. Do not proceed until they pass.

2. **Lint**: Run the project's lint command (e.g., `yarn lint`, `npm run lint`)
   - Auto-fix if possible. Manual fix if auto-fix fails.

3. **Type check / Build**: Run the build command (e.g., `yarn build`, `tsc --noEmit`)
   - Fix all type errors before proceeding.

4. **Code review checks**: Run `devflow check` if available
   - Address any findings. These are automated review rules.

If ANY verification step fails, fix the issue and re-run. Do not skip.

## Step 2: Commit

1. Stage all changes: `git add -A`
2. Review what's staged: `git status` and `git diff --cached`
3. Ensure no secrets or credentials are staged (check for `.env`, `credentials.*`, API keys)
4. Write a clear commit message following the project's conventions
5. Commit: `git commit -m "<message>"`

If there are multiple logical changes, create multiple commits (one per concern).

## Step 3: Push

```bash
git push -u origin HEAD
```
````

If the push is rejected (e.g., force push needed), STOP and ask the developer. Never force push without explicit permission.

## Step 4: Create Pull Request

Detect the VCS provider from the git remote and create a PR:

- **GitHub**: `gh pr create --title "<title>" --body "<body>"`
- **GitLab**: `glab mr create --title "<title>" --description "<body>"`

The PR body should include:

- Summary of changes (2-3 bullet points)
- Link to the ticket/issue if identifiable from the branch name
- Any notable decisions or trade-offs

If a PR already exists for this branch, skip creation and provide the URL.

## Step 5: Retain Learnings

Use Hindsight to retain what was learned during this session:

```
retain("<project>: <what was done and any important decisions>", tags=["<project>", "feature"])
retain("<project>: <any gotchas or non-obvious patterns discovered>", tags=["<project>", "gotcha"])
```

Only retain things that would be useful in future sessions. Skip if nothing novel was learned.

## Step 6: Summary

Output a completion summary:

```
## Task Complete ✓

**Branch**: feat/MES-1234
**PR**: https://github.com/org/repo/pull/123
**Commits**: 3
**Verification**: All passed (tests, lint, build, devflow check)

### To clean up the worktree, run:
devflow done feat/MES-1234
```

Always tell the developer the `devflow done` command to run for cleanup.

````

### Part 2: The CLI Command (`devflow done`)

Create `lib/done.sh`:

```bash
#!/usr/bin/env bash
# devflow done — clean up a completed work session

set -euo pipefail

usage() {
  cat <<EOF
Usage: devflow done <branch-name> [options]

Clean up a completed work session: close agent session, merge/remove worktree.

Arguments:
  <branch-name>    The branch to clean up (e.g., feat/MES-1234)

Options:
  --keep-branch    Don't delete the remote branch after merge
  --no-merge       Remove worktree without merging (discard changes)
  --force          Force cleanup even if there are uncommitted changes
  -h, --help       Show this help

Examples:
  devflow done feat/MES-1234
  devflow done feat/MES-1234 --keep-branch
  devflow done feat/MES-1234 --no-merge    # discard work
EOF
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  local branch="$1"
  shift

  local keep_branch=false
  local no_merge=false
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep-branch)  keep_branch=true; shift ;;
      --no-merge)     no_merge=true; shift ;;
      --force)        force=true; shift ;;
      -h|--help)      usage; exit 0 ;;
      *)              echo "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  echo "→ Cleaning up session: $branch"

  # Step 1: Close agent-deck session (if exists)
  local session_id
  session_id="$(agent-deck list --json 2>/dev/null | jq -r ".[] | select(.branch == \"$branch\") | .id" 2>/dev/null || true)"

  if [[ -n "$session_id" ]]; then
    echo "→ Closing agent-deck session: $session_id"
    agent-deck remove "$session_id" 2>/dev/null || true
  else
    echo "  No active agent-deck session found for $branch"
  fi

  # Step 2: Handle worktree
  if [[ "$no_merge" == "true" ]]; then
    echo "→ Removing worktree (no merge)..."
    if [[ "$force" == "true" ]]; then
      wt drop "$branch" --force 2>/dev/null || git worktree remove "$branch" --force
    else
      wt drop "$branch" 2>/dev/null || git worktree remove "$branch"
    fi
  else
    echo "→ Parking worktree and removing..."
    # wt park stashes changes and returns to main
    wt park 2>/dev/null || true
    wt drop "$branch" 2>/dev/null || git worktree remove "$branch" 2>/dev/null || true
  fi

  # Step 3: Clean up local branch (if worktree is gone)
  if ! git worktree list | grep -q "$branch"; then
    echo "→ Cleaning up local branch..."
    git branch -d "$branch" 2>/dev/null || git branch -D "$branch" 2>/dev/null || true
  fi

  # Step 4: Clean up remote branch (unless --keep-branch)
  if [[ "$keep_branch" == "false" && "$no_merge" == "false" ]]; then
    echo "→ Note: Remote branch will be cleaned up when PR is merged."
    echo "  To delete now: git push origin --delete $branch"
  fi

  echo ""
  echo "✓ Session cleaned up: $branch"
}

main "$@"
````

### Step 3: Register in `bin/devflow`

```bash
# In bin/devflow case statement:
done)
  shift
  source "$DEVFLOW_DIR/lib/done.sh"
  main "$@"
  ;;
```

Update help text:

```
Commands:
  init          One-time project setup
  work          Start a new work session
  done          Clean up a completed work session
```

### Step 4: Register the skill

Update `skills/registry.json` (or wherever skills are registered) to include the done skill:

```json
{
  "process-discipline/done": {
    "name": "done",
    "description": "Complete a task: verify, commit, push, create PR, retain learnings",
    "trigger": "task completion",
    "type": "rigid"
  }
}
```

## Acceptance Criteria

- [ ] `skills/process-discipline/done.md` exists and follows the rigid skill format
- [ ] The skill runs verification (tests, lint, build, devflow check) before committing
- [ ] The skill commits, pushes, and creates a PR
- [ ] The skill retains learnings to Hindsight
- [ ] The skill outputs a summary with the `devflow done` command
- [ ] `devflow done feat/MES-1234` closes the agent-deck session
- [ ] `devflow done feat/MES-1234` removes the worktree
- [ ] `devflow done feat/MES-1234` cleans up the local branch
- [ ] `devflow done feat/MES-1234 --no-merge` removes worktree without merging
- [ ] `devflow done feat/MES-1234 --keep-branch` preserves the remote branch
- [ ] `devflow done` with no arguments shows help
- [ ] `bin/devflow --help` lists the `done` command
- [ ] The skill is registered and discoverable by agent-deck

## Technical Notes

- The skill is type `rigid` — agents must follow it exactly, no shortcuts
- The skill should detect the project's test/lint/build commands from `package.json`, `Makefile`, `pyproject.toml`, etc. A hardcoded command won't work across projects.
- `devflow check` may not be available in all projects — the skill should check availability before running
- The `devflow done` CLI command should be safe to run even if the agent-side cleanup already happened (idempotent)
- agent-deck's `remove` command may have different syntax — check `agent-deck help remove`
- `wt drop` removes the worktree AND deletes the branch. `git worktree remove` only removes the worktree. Be careful about which to use.
- The skill's PR creation should use the VCS detection from ARCH-P1-008 once that's implemented

## Verification

```bash
# 1. Create a test work session
devflow work feat/test-done-001
# ... make some changes in the worktree ...

# 2. In the agent session, trigger the done skill
# (say "task is done" or equivalent)
# Expected: agent runs verification, commits, pushes, creates PR

# 3. Run CLI cleanup
devflow done feat/test-done-001
# Expected: session closed, worktree removed, branch cleaned up

# 4. Verify cleanup
agent-deck list | grep -v "test-done-001"  # should not appear
git worktree list | grep -v "test-done-001"  # should not appear
git branch | grep -v "test-done-001"  # should not appear

# 5. Test --no-merge
devflow work feat/test-done-002
devflow done feat/test-done-002 --no-merge
# Expected: worktree removed, no merge attempted

# 6. Test idempotency
devflow done feat/test-done-001  # already cleaned up
# Expected: no errors, graceful no-op
```
