---
id: FEAT-new-feature-task-management-awareness
title: "New Feature Skill: Task Management Awareness"
priority: P1
category: feature
status: done
depends_on:
  - SPIKE-kanban-board-integration
estimated_effort: M
files_touched:
  - devflow-plugin/commands/new-feature.md
completed_date: "2026-03-06"
---

# New Feature Skill: Task Management Awareness

## Context

The `new-feature` skill had no integration with project management tools. Developers needed to manually copy ticket context into the session. This task extended the skill to auto-fetch ticket details from whatever project management MCP is available.

## What Was Built

Extended `devflow-plugin/commands/new-feature.md` to:

1. **Accept arguments**: `$ARGUMENTS` now supports `<ticket-id> [extra context]` — e.g., `MES-3716 "focus on the API layer"`

2. **Detect project management MCP**: At startup, checks if any PM MCP is available:
   - Jira (Atlassian): `mcp__claude_ai_Atlassian__getJiraIssue`
   - Linear: `mcp__linear__*` tools
   - GitHub Issues: `mcp__github__*` tools
   - If none found: informs user and continues without ticket context

3. **Auto-fetch ticket details**: If ticket ID + compatible MCP found, fetches:
   - Title, type, priority, status, description/acceptance criteria

4. **Suggest descriptive branch name**: If the current branch is generic (e.g., `feat/MES-1234`), suggests renaming to `feat/MES-1234/slugified-title`

5. **Populates brainstorming context**: Feeds ticket details into the brainstorming skill for richer design sessions

## Why

Eliminates the manual copy-paste step of ticket context. The agent now starts with full awareness of what needs to be built, reducing misalignment between ticket requirements and implementation.

## Future Work

Full task management board integration (pick task → start session) is tracked in `tasks/P3/SPIKE-kanban-board-integration.md`.
