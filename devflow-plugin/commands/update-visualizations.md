---
description: [0.17.0] Analyze recent changes and update affected architecture visualizations
---

# Update Visualizations

You are updating project visualizations (mermaid diagrams) based on recent changes. This skill works standalone — it can be used in any project, not just devflow.

> **Diagram complexity** — before drawing, rate it:
> - 🟢 **simple** — linear / ≤4 nodes → plain ASCII is fine.
> - 🟡 **moderate** — fork-join, 5–8 nodes, or one crossing → OFFER a rendered Excalidraw (the **render-diagram** skill).
> - 🔴 **complex** — bidirectional, multi-lane, >8 nodes, or cycles → render with the **render-diagram** skill AND show it inline via the Read tool.

## Step 1: Locate Visualization Config

Check for visualization configuration in this order:
1. `.devflow/visualizations.json` (project-specific)
2. `~/.config/devflow/visualizations.json` (global)
3. If neither exists, look for common locations: `docs/visualizations/`, `visualizations/`, `docs/diagrams/`
4. If no visualizations folder found, ask the user if they'd like to create one (default: `docs/visualizations/`)

Read the config to determine:
- `path`: Where visualizations live
- `style`: Which color palette and init settings to use (default: "devflow")
- `categories`: Which subfolder categories exist
- `format`: Which diagram format to emit — `mermaid` (default) or `excalidraw`. Treat a missing/absent `format` key as `mermaid` (backward-compatible).

### Step 1b: Branch on `format` (opt-in Excalidraw)

`format` selects HOW diagrams are produced for the rest of this skill — it does not change WHICH visualizations get updated:

- **`mermaid` (default / absent)** — keep the existing behavior unchanged: edit/create inline Mermaid fenced blocks directly in the `.md` files, following all the steps below.
- **`excalidraw` (opt-in)** — for each affected visualization, instead of writing Mermaid, produce/update the diagram via the **`/devflow:render-diagram`** skill: author (or edit) the `.excalidraw` next to the visualization `.md`, run `devflow visualizations render <file>.excalidraw`, **Read the resulting PNG to show it inline during this session**, and embed it in the visualization `.md` with `![<alt>](./<name>.png "<Title>")`. Commit the `.excalidraw` + `.svg` + `.png` alongside the `.md`. Everything else about Steps 2–8 (which files to touch, the index, the commit) is identical — only the diagram body changes from a Mermaid block to a rendered-PNG embed.

The rest of this skill is written for the `mermaid` path; when `format` is `excalidraw`, apply the render-diagram substitution wherever a Mermaid block would otherwise be written.

## Step 2: Analyze Changes

Run `git diff HEAD~1` (or `git diff` for unstaged changes) to understand what was modified.

If the user provided a description via `$ARGUMENTS`, use that as additional context for what changed.

## Step 3: Read the Visualization Index

Read `<viz-path>/README.md` to understand:
- What visualizations currently exist
- Which categories are defined
- The style guide being used

## Step 4: Map Changes to Visualizations

For each changed file, determine which visualization(s) it might affect. Use these heuristics:

**For devflow projects:**
- `lib/services.sh`, `docker/docker-compose.yml` → `architecture/runtime-architecture.md`
- `lib/sync.sh`, MCP/skill config changes → `architecture/sync-architecture.md`
- `lib/worktree.sh`, skill workflow changes → `workflows/development-workflow.md`
- `lib/init.sh` setup changes → `architecture/devflow-ecosystem.md`
- `bin/devflow` (new commands) → `architecture/devflow-ecosystem.md`
- New skill/plugin → May need a new diagram in `integrations/`

**For general projects:**
- New API endpoints → `architecture/` diagrams
- Database schema changes → `architecture/data-model.md`
- New integrations/services → `integrations/` diagrams
- Workflow/process changes → `workflows/` diagrams

## Step 5: Update or Create Visualizations

For each affected visualization:

1. **Read** the current file
2. **Identify** what's outdated (missing nodes, wrong connections, stale labels)
3. **Update** the mermaid diagrams to reflect the new reality
4. Keep the style conventions from the README style guide:
   - YAML frontmatter with tags and related links
   - `%%{init}` blocks for spacing
   - Consistent classDef color palette
   - Horizontal rules between sections
   - Numbered section headings

If a visualization doesn't exist for a new component, **create one** in the appropriate subfolder using the style guide template.

> **If `format` is `excalidraw`** (per Step 1b): produce each diagram via `/devflow:render-diagram` (author `.excalidraw` → `devflow visualizations render` → Read the PNG to show it inline → embed `![](./x.png)` in the `.md`) instead of writing a Mermaid block. The set of visualizations to update is the same; only the diagram body differs.

## Step 6: Create Default Visualizations (First Run)

If the visualization folder was just created (no existing diagrams), create these defaults:

### `architecture/system-overview.md`
A high-level diagram showing the project's main components and how they connect. Analyze the project structure (package.json, directory layout, config files) to infer the architecture.

### `workflows/main-workflow.md`
A diagram showing the primary workflow (e.g., request lifecycle, data pipeline, build process). Infer from the project type.

## Step 7: Update the Index

If new files were created, update `<viz-path>/README.md`:
- Add entries to the navigation table
- Update the related links in frontmatter

## Step 8: Commit

Stage and commit visualization changes:
```bash
git add <viz-path>/
git commit -m "docs: update visualizations for [brief description]"
```

$ARGUMENTS
