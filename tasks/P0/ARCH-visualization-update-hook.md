---
id: ARCH-visualization-update-hook
title: "Standalone Visualization System — Skill, Plugin, CLI Config, Auto-Update Hook"
priority: P0
category: architecture
status: in-progress
depends_on: []
estimated_effort: XL
files_to_touch:
  - visualizations/ (new — full folder structure)
  - visualizations/README.md (new — index + style guide)
  - skills/visualizations/update-visualizations.md (new)
  - skills/visualizations/visualizations-config.md (new)
  - skills/registry.json (update — add 2 entries)
  - lib/visualizations.sh (new — CLI config management)
  - bin/devflow (update — add visualizations command)
  - devflow-plugin/ (regenerated via skills convert)
---

# Standalone Visualization System — Skill, Plugin, CLI Config, Auto-Update Hook

## Context

The devflow ecosystem has visualization files (mermaid diagrams) documenting the architecture, workflow, and tool connections. When tasks are completed — especially architecture changes, new features, or bug fixes that alter the system — the visualizations should be updated to reflect the new reality.

Currently, visualization updates are manual and easily forgotten, leading to stale documentation that diverges from the actual system.

## Problem Statement

After completing a task, there is no mechanism to:
1. Check if the change impacts any existing visualization
2. Prompt the agent to update affected diagrams
3. Create new diagrams when entirely new components are added
4. Keep the visualizations in sync with the evolving architecture

Additionally, the visualization system should:
5. Work as a **standalone skill and plugin** — project-independent, usable in any codebase
6. **Create default visualizations** when first invoked on a project with none
7. Provide a **config command** to set visualization location, style presets, and output preferences

## Desired Outcome

### 1. Standalone Skill + Plugin

A visualization skill that:
- Works independently of the devflow project — any project can use it
- Auto-detects if a project has a visualization folder configured
- Creates default architectural visualizations on first invocation (project structure, data flow)
- Updates existing visualizations based on git diffs
- Follows a consistent mermaid style guide (colors, spacing, frontmatter)

### 2. CLI Config Command

`devflow visualizations config` to manage:
- **Path**: Where visualizations live (`--path <dir>`)
- **Style preset**: Default color palette and mermaid init settings
- **Output format**: Which diagram categories to create by default
- **Symlink targets**: Additional directories that should symlink to the visualization folder

### 3. Auto-Update Hook

A Stop hook that reminds about visualization updates, plus integration with the `/devflow:done` workflow.

## Visualization Folder Structure

The visualizations live in the devflow project as the source of truth:

```
~/dev/devflow/visualizations/
├── README.md                          # Index, navigation, and style guide
├── architecture/                      # System architecture diagrams
│   ├── devflow-ecosystem.md           # The 6-layer tool ecosystem
│   ├── runtime-architecture.md        # Docker, CLIs, config files
│   └── sync-architecture.md           # Skills/MCP sync flow (future)
├── workflows/                         # Process flow diagrams
│   ├── development-workflow.md        # Full SDD workflow: idea → MR
│   ├── devflow-work-flow.md           # The devflow work command flow (future)
│   └── session-lifecycle.md           # Session create → conductor → done → cleanup (future)
├── integrations/                      # Tool-specific integration diagrams
│   ├── agent-deck-integration.md      # How agent-deck connects to everything (future)
│   ├── hindsight-data-flow.md         # Memory recall/retain/reflect patterns (future)
│   └── langfuse-trace-flow.md         # What gets traced and where (future)
└── decisions/                         # Visual ADRs
    └── (created as needed)
```

**Symlink to aircall visualizations:**
```bash
ln -sf ~/dev/devflow/visualizations ~/dev/aircall/visualizations/devflow
```

## Implementation Guide

### Step 1: Create Visualization Folder Structure

1. Create `~/dev/devflow/visualizations/` with subdirectories: `architecture/`, `workflows/`, `integrations/`, `decisions/`
2. Move existing files:
   - `~/dev/aircall/visualizations/devflow-ecosystem.md` → `~/dev/devflow/visualizations/architecture/devflow-ecosystem.md`
   - `~/dev/aircall/visualizations/development-workflow.md` → `~/dev/devflow/visualizations/workflows/development-workflow.md`
3. Update internal cross-references (the `related:` frontmatter and `[[wiki-links]]`) in moved files
4. Create symlink: `ln -sf ~/dev/devflow/visualizations ~/dev/aircall/visualizations/devflow`
5. Update `~/dev/aircall/visualizations/README.md` to reference `devflow/` subfolder
6. Remove old files from aircall visualizations root
7. Create `~/dev/devflow/visualizations/README.md` as the visualization index + style guide

### Step 2: Create Source Skills

Create `skills/visualizations/update-visualizations.md`:
- Analyzes git diffs to determine affected visualizations
- Maps file changes to diagram categories
- Updates existing diagrams or creates new ones
- Updates the index README
- Commits visualization changes

Create `skills/visualizations/visualizations-config.md`:
- Configures visualization location, style presets, output format
- Stores config in `~/.config/devflow/visualizations.json`
- Supports per-project overrides via `.devflow/visualizations.json`

### Step 3: Update Registry

Add both skills to `skills/registry.json` under a new "visualizations" category, layer 5.

### Step 4: Create CLI Library

Create `lib/visualizations.sh` with:
- `devflow_visualizations` dispatcher (config, list, open, update)
- `viz_config` — read/write visualization config
- `viz_list` — list all visualization files
- `viz_open` — open a visualization in browser (mermaid.live) or VS Code

### Step 5: Update CLI Entry Point

Add `visualizations` command to `bin/devflow` case statement, source the new library.

### Step 6: Regenerate Plugin

Run `devflow skills convert --marketplace` to regenerate the plugin with:
- New `update-visualizations` command
- New `visualizations-config` command
- Updated Stop hook mentioning visualization updates

### Step 7: Update Stop Hook

The hook template in `skills_convert` should include visualization reminder:
```
Session ending. Consider running /devflow:update-visualizations to update architecture diagrams. Run /devflow:session-summary to log metrics.
```

## Mermaid Style Guide

**Color palette** (consistent across all files):
| Component | Color | Hex |
|-----------|-------|-----|
| Hindsight | Purple | `#7c3aed` |
| Agent Deck | Blue | `#3b82f6` |
| Worktrunk | Green | `#059669` |
| Continue.dev | Amber | `#d97706` |
| Skills/Marketplace | Pink | `#be185d` |
| Langfuse | Cyan | `#0891b2` |
| Conductor | Amber variant | `#f59e0b` |
| CLI/Terminal | Gray | `#374151` |

**Init block** (every mermaid diagram):
```
%%{init: {'flowchart': {'rankSpacing': 50, 'nodeSpacing': 30, 'diagramPadding': 15}}}%%
```

**Frontmatter** (every visualization file):
```yaml
---
tags: [devflow, <category>, <specific-tags>]
related: ["[[other-file]]"]
---
```

## Acceptance Criteria

- [ ] `~/dev/devflow/visualizations/` exists with architecture/, workflows/, integrations/, decisions/ subfolders
- [ ] Existing visualization files moved to new structure with correct subfolder placement
- [ ] Internal cross-references updated in moved files
- [ ] `~/dev/aircall/visualizations/devflow` is a symlink to `~/dev/devflow/visualizations/`
- [ ] `~/dev/aircall/visualizations/README.md` updated to reference devflow/ subfolder
- [ ] Old devflow-ecosystem.md and development-workflow.md removed from aircall visualizations root
- [ ] `visualizations/README.md` index created with navigation + style guide
- [ ] `skills/visualizations/update-visualizations.md` created
- [ ] `skills/visualizations/visualizations-config.md` created
- [ ] `skills/registry.json` updated with 2 new entries
- [ ] `lib/visualizations.sh` created with config/list/open/update subcommands
- [ ] `bin/devflow` updated with visualizations command
- [ ] Plugin regenerated via `devflow skills convert --marketplace`
- [ ] Plugin validates with `claude plugin validate`
- [ ] Stop hook includes visualization update reminder
- [ ] When invoked on a project with no visualizations, default diagrams are created

## Verification

```bash
# Check folder structure
ls -la ~/dev/devflow/visualizations/
ls -la ~/dev/devflow/visualizations/architecture/
ls -la ~/dev/devflow/visualizations/workflows/

# Check symlink
ls -la ~/dev/aircall/visualizations/devflow

# Check skills exist
cat ~/dev/devflow/skills/visualizations/update-visualizations.md
cat ~/dev/devflow/skills/visualizations/visualizations-config.md

# Check registry
jq '.skills[] | select(.category == "visualizations")' ~/dev/devflow/skills/registry.json

# Check CLI
~/dev/devflow/bin/devflow visualizations --help

# Check plugin
cat ~/dev/devflow/devflow-plugin/hooks/hooks.json
claude plugin validate ~/dev/devflow/devflow-plugin 2>&1

# Test the command (in a Claude Code session)
# /devflow:update-visualizations "Added visualization system"
```

## Technical Notes

- **The hook is a reminder, not an enforcer.** We can't force visualization updates, but we can make it a habit by including it in the `/devflow:done` workflow and the Stop hook reminder.

- **Git tracking:** The `~/dev/devflow/visualizations/` folder should be committed to the devflow git repo. Since aircall visualizations are symlinked, they'll pick up changes automatically.

- **Standalone operation:** The skill must work in any project. When no config exists, it should prompt to create one. Default config creates visualizations in `<project-root>/docs/visualizations/`.

- **New visualizations:** When entirely new components are added, the command should detect there's no existing diagram and offer to create one from templates in the style guide.
