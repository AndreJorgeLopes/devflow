# Finish-Feature Visualization Integration

**Date:** 2026-03-10
**Status:** Approved
**Branch:** feat/review-pr-description

## Problem

The `finish-feature` skill completes features without checking whether architecture/workflow visualizations need updating. Visualization updates are manual and easily forgotten, causing diagrams to drift from reality. Additionally, several commits have landed since the last visualization edit that likely require diagram updates.

## Deliverables

### 1. Skill Fix — New Visualization Step in finish-feature.md

Insert a new step between current step 3 (stage & commit) and step 4 (PR description strategy), shifting all subsequent steps down by one.

**Behavior:**

- **Fast-path guard:** Before running any analysis, check if a visualization directory exists (resolve via `viz_resolve_path()` logic: `.devflow/visualizations.json`, `~/.config/devflow/visualizations.json`, or common paths like `visualizations/`, `docs/visualizations/`). If no visualization directory exists, skip this step silently with a one-line note ("No visualization directory found, skipping"). Do NOT trigger first-run setup inside the finish-feature flow.
- **Skill loading:** The finish-feature skill must include an explicit `Read` instruction for the full path to the update-visualizations skill (`skills/visualizations/update-visualizations.md`), since skills in `skills/` are not auto-discovered by Claude Code.
- **Diff range:** Instruct the update-visualizations skill to analyze `main..HEAD` (the full feature branch diff), not the default `HEAD~1`. Pass this as context/arguments when invoking the skill.
- **Commit coordination:** The finish-feature step handles the commit itself. When invoking the update-visualizations skill logic, skip the skill's built-in Step 8 (commit) — finish-feature will stage and commit the visualization changes as a separate commit after user confirmation.
- Determine which visualization files are affected and what changes are needed
- Present a text TLDR to the user: which diagrams would be updated/created, plus a gist of changes (no mermaid rendering in terminal — just describe what was added/removed/modified)
- If no updates needed, say so and move on
- If updates proposed, ask user to confirm before applying
- After applying, auto-commit visualization changes as a separate commit from code changes

### 2. Immediate Visualization Audit — Two-Phase Agent Team

This is a one-time operational task bundled with the skill fix for convenience. It catches up the existing diagrams to reflect changes that landed since the last visualization edit.

**Phase 1: Audit Agent (coordinator)**
- Find the last commit that touched `visualizations/` files
- Collect all commits from that point to HEAD on main
- Analyze diffs to identify architectural/workflow changes
- Map changes to affected visualization files
- Produce a structured brief per affected diagram: what changed, what needs updating, relevant commit refs

**Phase 2: Diagram Agents (parallel specialists)**
- One sub-agent per affected diagram file
- Each receives only: current diagram content, relevant change brief from Phase 1, style guide from `visualizations/README.md`
- Each agent updates its diagram and produces a TLDR of changes
- Results collected, presented to user for confirmation, then committed

**Expected diagrams to audit:**
- `devflow-ecosystem.md` — hooks architecture (PostToolUse, Stop hook PR detection), new skills
- `development-workflow.md` — Phase 4 visualization check step (from deliverable 1)
- `code-review-architecture.md` — PR description strategy, dual-mode review updates

## Execution Architecture

**Parallel Track A — Skill fix agent:**
- Edit `devflow-plugin/commands/finish-feature.md` to insert new visualization step
- Single agent, small focused edit

**Parallel Track B — Visualization audit:**
- Phase 1: Coordinator agent analyzes commits, produces per-diagram briefs
- Phase 2: Up to 3 parallel specialist agents (one per diagram), each with clean context

Track A and Track B run simultaneously (independent). Track B Phase 2 depends on Phase 1.

**Commit strategy:**
- Track A: one commit for the skill edit
- Track B: one commit for all visualization updates (grouped)

## Design Decisions

- **Always run analysis, with fast-path guard** — always invoke the skill when visualizations exist, but skip instantly if no visualization directory is found. This keeps trivial projects fast while ensuring visualization-enabled projects always get checked.
- **Explicit skill loading** — use `Read` for the full skill path to avoid the known auto-discovery gotcha with skills in `skills/`
- **Feature-branch diff range** — use `main..HEAD` instead of the skill's default `HEAD~1`, since finish-feature covers the entire feature branch
- **Finish-feature owns the commit** — skip the update-visualizations skill's built-in commit step to avoid double-commits; finish-feature handles staging and committing
- **User confirmation required** — present TLDR before applying changes, user approves or skips
- **Text-only summaries** — mermaid can't render in terminal, so describe changes in plain language
- **Separate commits** — visualization updates are logically distinct from code changes
- **Clean context separation** — audit coordinator doesn't edit diagrams; diagram agents don't analyze commits
