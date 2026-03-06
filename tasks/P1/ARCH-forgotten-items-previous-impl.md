---
id: ARCH-forgotten-items-previous-impl
title: "Forgotten Items From Previous Implementation"
priority: P1
category: architecture
status: open
depends_on: []
estimated_effort: L
files_to_touch:
  - bin/devflow
  - lib/init.sh
  - lib/worktree.sh
  - devflow-plugin/skills/**
  - visualizations/**
---

# Forgotten Items From Previous Implementation

## Context

The previous implementation round delivered the core devflow structure but left several items incomplete or incorrectly implemented. These are not new features — they are gaps in what was already specified and partially built. Three distinct areas need attention: agent-deck group/session wiring, Layer 5 marketplace identity, and visualization file organization.

## Problem Statement

### 1. Groups and Sessions — Not Wired End-to-End

`devflow init` may create agent-deck groups (project, project/features, project/bugfixes, project/reviews), but it's unverified whether:

- The groups actually get created successfully
- `devflow worktree --agent` assigns sessions to the correct group based on branch prefix
- The group hierarchy works as expected in `agent-deck list`

### 2. Marketplace as Layer 5 — Incomplete Identity

The generated plugin at `devflow-plugin/` IS Layer 5 (Plugin Marketplace), but this identity isn't reflected everywhere:

- `bin/devflow` help text may still say "CLAUDE.md" for Layer 5 instead of "Plugin Marketplace"
- Visualization files don't reference the marketplace
- `devflow skills convert` should produce the canonical Layer 5 artifact
- `devflow init` doesn't offer to install the plugin via `claude plugin install`

### 3. Visualization Files — Wrong Location and Naming

Visualization files currently live in `~/dev/aircall/visualizations/` mixed with numbered messaging knowledge-base files. Devflow visualizations should:

- Live in `/Users/andrejorgelopes/dev/devflow/visualizations/` as source of truth
- Be symlinked to `~/dev/aircall/visualizations/devflow/` (a dedicated subfolder)
- NOT use numbered prefixes (`10-`, `11-`) — those are a messaging convention
- Use descriptive names (`devflow-ecosystem.md`, `development-workflow.md`)

## Desired Outcome

1. `devflow init` reliably creates agent-deck groups, and sessions are correctly assigned
2. Layer 5 is consistently referred to as "Plugin Marketplace" across all devflow artifacts
3. Visualization files live in the devflow repo with descriptive names and are symlinked to the shared location

## Implementation Guide

### Part 1: Groups and Sessions Audit

#### Step 1: Test group creation in `devflow init`

Run `devflow init` in a test project and verify:

```bash
agent-deck group list | grep "<project>"
```

If groups aren't created, find the relevant code in `lib/init.sh` and fix it.

#### Step 2: Verify session-to-group assignment

In `lib/worktree.sh`, trace the code path from branch creation to `agent-deck add`. Confirm the `-g` flag is passed with the correct group derived from the branch prefix:

- `feat/MES-123` → `-g <project>/features`
- `fix/MES-456` → `-g <project>/bugfixes`
- `review/MES-789` → `-g <project>/reviews`

#### Step 3: Test end-to-end

```bash
devflow worktree feat/test-groups --agent claude
agent-deck list  # should show session in <project>/features
```

### Part 2: Marketplace as Layer 5

#### Step 1: Update `bin/devflow` help text

Find the layer listing in `bin/devflow` (likely in a help or info subcommand). Change Layer 5 from whatever it currently says to:

```
Layer 5: Plugin Marketplace (devflow-plugin/)
```

#### Step 2: Update visualization references

Any visualization file that depicts the layer stack should reference "Plugin Marketplace" for Layer 5.

#### Step 3: Update `devflow init` to offer plugin install

At the end of `devflow init`, add:

```bash
echo "Install devflow plugin for Claude Code?"
read -r answer
if [[ "$answer" =~ ^[Yy] ]]; then
  claude plugin install ./devflow-plugin
fi
```

#### Step 4: Ensure `devflow skills convert` output is Layer 5 artifact

The convert command should output skills in the format expected by the plugin marketplace, not just raw markdown.

### Part 3: Visualization File Relocation

#### Step 1: Create the devflow visualizations directory

```bash
mkdir -p /Users/andrejorgelopes/dev/devflow/visualizations
```

#### Step 2: Move/rename visualization files

Move any devflow-related visualization files from `~/dev/aircall/visualizations/` to `/Users/andrejorgelopes/dev/devflow/visualizations/`. Rename them:

- Remove numbered prefixes
- Use descriptive kebab-case names: `devflow-ecosystem.md`, `development-workflow.md`, `layer-architecture.md`

#### Step 3: Create symlinks

```bash
mkdir -p ~/dev/aircall/visualizations/devflow
ln -sf /Users/andrejorgelopes/dev/devflow/visualizations/*.md ~/dev/aircall/visualizations/devflow/
```

#### Step 4: Update any references

Search the devflow codebase for hardcoded paths to the old visualization locations and update them.

## Acceptance Criteria

- [ ] `devflow init` creates agent-deck groups: `<project>`, `<project>/features`, `<project>/bugfixes`, `<project>/reviews`
- [ ] `agent-deck group list` shows the groups after init
- [ ] Sessions created via `devflow worktree` appear in the correct group in `agent-deck list`
- [ ] `bin/devflow` help text references "Plugin Marketplace" for Layer 5
- [ ] `devflow init` offers to install the devflow plugin
- [ ] Visualization files live in `/Users/andrejorgelopes/dev/devflow/visualizations/` with descriptive names (no numbered prefixes)
- [ ] Symlinks exist at `~/dev/aircall/visualizations/devflow/` pointing to the source files
- [ ] No devflow visualization files remain directly in `~/dev/aircall/visualizations/` (only in the `devflow/` subfolder)

## Technical Notes

- agent-deck group creation syntax: `agent-deck group create <name>` — verify exact syntax from `agent-deck help group`
- The `claude plugin install` command may not exist yet or may have different syntax — check Claude Code docs. If it doesn't exist, use whatever the current plugin installation mechanism is.
- When moving visualization files, check git history to preserve authorship if they're tracked
- The numbered prefix convention (`10-`, `11-`) is specific to the messaging knowledge base visualization system — devflow should NOT adopt it

## Verification

```bash
# Part 1: Groups
devflow init  # in a test project
agent-deck group list
# Expected: project groups visible

# Part 2: Layer 5
devflow --help | grep -i "marketplace\|layer 5"
# Expected: "Plugin Marketplace" mentioned

# Part 3: Visualizations
ls /Users/andrejorgelopes/dev/devflow/visualizations/
# Expected: descriptive names, no numbered prefixes

ls -la ~/dev/aircall/visualizations/devflow/
# Expected: symlinks pointing to devflow/visualizations/

ls ~/dev/aircall/visualizations/ | grep -E "^[0-9]+-.*devflow"
# Expected: no results (no numbered devflow files in root)
```
