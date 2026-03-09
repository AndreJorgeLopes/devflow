# Superpowers Wrapper Architecture — Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a wrapper layer so devflow can extend superpowers skills without modifying upstream files.

**Architecture:** Thin wrapper skills in `skills/superpowers-wrappers/` that use event-based triggers to add devflow-specific behavior after superpowers skills complete specific steps. Priority is enforced via `~/.claude/CLAUDE.md` (user-global, managed by devflow init).

**Tech Stack:** Markdown skills, bash (init.sh), git

---

## Problem

Devflow modified `superpowers:writing-plans` directly in the Claude Code plugin cache (`~/.claude/plugins/cache/claude-plugins-official/superpowers/4.3.1/`). This local commit (`e07422e`) will be overwritten on the next superpowers update, losing the agent-deck parallel session handoff feature.

## Solution

### 1. Wrapper Skills (`skills/superpowers-wrappers/`)

Each wrapper:
- Targets a specific superpowers skill by name
- Uses **event-based triggers**: "after X happens in the superpowers skill, also do Y"
- Contains only the devflow delta — no duplication of upstream content
- Is resilient to upstream restructuring (keys on behavior, not section names)

**Template pattern:**
```markdown
---
name: <same-name-as-superpowers-skill>
description: [devflow v0.1.0] Extends superpowers:<skill> with <devflow addition>
---

This skill extends superpowers:<skill>. Follow the superpowers skill completely.
When the following events occur, apply these additions:

## After: <event description>

<devflow-specific behavior>
```

### 2. Priority Rule (`~/.claude/CLAUDE.md`)

Added to the devflow-managed section of the user's global CLAUDE.md:
- Tells Claude to invoke both skills: superpowers first, then devflow extension
- Ensures devflow wrappers are applied across all repos
- Managed by `devflow init` — no manual configuration needed

### 3. Init Integration (`lib/init.sh`)

- Adds the skill priority rule to `~/.claude/CLAUDE.md`
- Symlinks `skills/superpowers-wrappers/` into Claude Code's skill discovery path
- Idempotent — re-running init updates the rule if needed

### 4. Upstream Restoration

- Revert the local commit in superpowers plugin cache
- Superpowers goes back to vanilla upstream

## File Changes

| File | Action |
|------|--------|
| `skills/superpowers-wrappers/writing-plans.md` | Create — first wrapper (agent-deck handoff) |
| `skills/registry.json` | Update — add superpowers-wrappers category |
| `devflow-plugin/commands/writing-plans.md` | Create — expose as `/devflow:writing-plans` |
| `lib/init.sh` | Update — add priority rule to CLAUDE.md template, symlink wrappers |
| `templates/CLAUDE.md.tmpl` | Update — add skill priority section |
| Superpowers plugin cache | Revert — restore upstream `writing-plans/SKILL.md` |

## Decisions

- **Composition over replacement**: Wrappers extend, not replace. Upstream changes flow through.
- **Event-based triggers over section-level overrides**: More resilient to upstream restructuring.
- **Global priority via `~/.claude/CLAUDE.md`**: Works across all repos without project-level config.
- **AGENTS.md is a symlink to CLAUDE.md**: Single source of truth, already implemented in init.sh.
