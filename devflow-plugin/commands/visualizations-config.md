---
description: [devflow v0.1.0] Configure visualization location, style presets, and output preferences
---

# Configure Visualizations

You are configuring the visualization system for a project. This sets up where visualizations live, what style to use, and which categories to create by default.

## Step 1: Determine Current Config

Check for existing configuration:
1. `.devflow/visualizations.json` in the current project
2. `~/.config/devflow/visualizations.json` as global default

If `$ARGUMENTS` contains specific flags, parse them:
- `--path <dir>` — set visualization directory
- `--style <preset>` — set style preset (devflow, minimal, custom)
- `--categories <list>` — comma-separated category folders to create
- `--global` — write to global config instead of project config
- `--show` — just display current config, don't modify

## Step 2: Interactive Setup (No Arguments)

If no arguments provided, guide the user through setup:

### 2a. Visualization Path

Ask: "Where should visualizations be stored?"

Options:
- `docs/visualizations/` (recommended for most projects)
- `visualizations/` (if docs/ doesn't exist)
- Custom path

### 2b. Style Preset

Ask: "Which style preset?"

Options:
- **devflow** — Full color palette with 10 classDefs, YAML frontmatter, init blocks (default)
- **minimal** — Simple black/white diagrams, no frontmatter, basic styling
- **custom** — User provides their own classDef colors

### 2c. Categories

Ask: "Which diagram categories?"

Default categories:
- `architecture/` — System architecture diagrams
- `workflows/` — Process flow diagrams
- `integrations/` — Tool/service integration diagrams
- `decisions/` — Visual ADRs

The user can add or remove categories.

## Step 3: Write Configuration

### Project config (`.devflow/visualizations.json`):

```json
{
  "path": "docs/visualizations",
  "style": "devflow",
  "categories": ["architecture", "workflows", "integrations", "decisions"],
  "init": {
    "flowchart": {
      "rankSpacing": 50,
      "nodeSpacing": 30,
      "diagramPadding": 15
    }
  },
  "colors": {
    "primary": "#3b82f6",
    "secondary": "#059669",
    "accent": "#be185d",
    "warning": "#d97706",
    "info": "#0891b2",
    "neutral": "#374151"
  },
  "frontmatter": true,
  "symlinks": []
}
```

### Global config (`~/.config/devflow/visualizations.json`):

Same schema but applies as default when no project config exists.

## Step 4: Create Folder Structure

Create the configured directory structure:

```bash
mkdir -p <path>/{<categories>}
```

## Step 5: Create README

Generate `<path>/README.md` with:
- Navigation table (empty initially)
- Style guide based on chosen preset
- Folder structure description
- Update instructions referencing `/devflow:update-visualizations`

## Step 6: Create .gitkeep Files

Add `.gitkeep` to empty category folders so git tracks them:

```bash
touch <path>/<category>/.gitkeep
```

## Step 7: Report

Summarize what was configured:
- Config file location
- Visualization path
- Style preset
- Categories created
- Next step: run `/devflow:update-visualizations` to create initial diagrams

$ARGUMENTS
