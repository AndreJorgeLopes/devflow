---
id: ARCH-plugin-dev-workflow
title: "Plugin Dev Workflow — Symlink-Based Command/Skill Discovery"
priority: P1
category: architecture
status: done
depends_on: []
estimated_effort: S
files_touched:
  - Makefile
  - README.md
  - devflow-plugin/commands/*.md
  - .claude/commands/plugin-sync.md
completed_date: "2026-03-09"
---

# Plugin Dev Workflow — Symlink-Based Command/Skill Discovery

## Problem

Claude Code discovers plugin commands from `~/.claude/plugins/cache/` which copies files at install time. Any change to a command file requires `claude plugin install` again, breaking dev iteration.

## What Was Built

1. **Symlink-based dev workflow**: Mirrors how `~/.claude/skills/` already works (e.g. `find-skills -> ../../.agents/skills/find-skills`). Created `~/.claude/commands/devflow/` as a symlink pointing directly to `devflow-plugin/commands/`, so edits are live on next Claude restart.

2. **Makefile targets**:
   - `make plugin-dev` — creates commands + skills symlinks, uninstalls plugin if present
   - `make plugin-unlink` — removes symlinks
   - `make plugin-install` — full marketplace register + install (for end users)

3. **Version badge in descriptions**: All command files now include `[devflow v0.1.0]` in the description frontmatter. Visible in the `/` menu to identify the source and detect if a stale installed plugin is shadowing the dev symlink.

4. **`plugin-sync` project-level skill**: `.claude/commands/plugin-sync.md` — checks symlink health, detects stale plugin installs, verifies version consistency. Only visible inside the devflow repo.

5. **README update**: Added "Claude Code Plugin" section documenting both end-user install and developer symlink workflows.

## Key Decision

Commands go in `~/.claude/commands/devflow/` (a subdirectory), not `~/.claude/commands/` directly. This keeps the root directory available for other tools to add their own command subdirectories — same pattern as the existing skills directory.
