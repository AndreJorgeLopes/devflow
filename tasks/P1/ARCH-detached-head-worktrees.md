---
id: ARCH-detached-head-worktrees
title: "Use detached HEADs for worktrees — never lock main branch"
priority: P1
category: architecture
status: in-progress
depends_on: []
estimated_effort: M
files_to_touch:
  - lib/worktree.sh
  - lib/utils.sh
  - devflow-plugin/commands/finish-feature.md
  - CLAUDE.md
---

## Problem

Git only allows one worktree per branch. If any worktree has `main` checked out,
no other worktree can use it. This blocks operations like `git checkout main` in
other worktrees and can interfere with worktree creation flows.

Current state: `devflow.feat-wrap-superpowers-skills` has `main` checked out,
blocking all other worktrees from using main directly.

## Industry Pattern

All major AI dev tools (OpenCode/Superpowers, Agent-deck, Claude Code worktree
isolation) follow the same pattern:
- Always create NEW branches for worktrees (`git worktree add <path> -b <branch> main`)
- Never check out main/master directly in a worktree
- Use detached HEAD when you need to be "at main's commit"
- Remove worktrees when done (don't leave them lingering on main)

## Implementation

### Task 1: Fix wt command in worktree.sh
`wt step -c` is incorrect — should be `wt switch --create`.

### Task 2: Add main-unlock guard
Add `_ensure_main_unlocked()` helper that detaches any worktree currently on main.
Call before worktree creation.

### Task 3: Update finish-feature cleanup
Step 10 should use detached HEAD when moving to the main worktree.

### Task 4: Document convention
Update CLAUDE.md with the detached HEAD worktree convention.

## Verification

- `git worktree list` should never show `[main]` on any worktree
- Creating multiple worktrees simultaneously should work without conflicts
- `devflow worktree <name>` should auto-detach any worktree that has main locked
