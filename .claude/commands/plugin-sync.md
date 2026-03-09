---
description: "[devflow-dev] Check if devflow commands/skills symlinks are healthy and no stale plugin is installed."
---

You are checking the devflow plugin development setup. Run these checks and report status:

## Checks

### 1. Commands symlink

```bash
ls -la ~/.claude/commands/devflow 2>/dev/null
```

- **Healthy**: symlink exists and points to this repo's `devflow-plugin/commands/`
- **Broken**: symlink missing, points elsewhere, or is a regular directory
- **Fix**: `make plugin-dev` (from the devflow repo root)

### 2. Skills symlink

```bash
ls -la ~/.claude/skills/devflow-recall 2>/dev/null
```

- **Healthy**: symlink exists and points to `devflow-plugin/skills/recall-before-task/`
- **Fix**: `make plugin-dev`

### 3. Stale plugin installed

```bash
cat ~/.claude/plugins/installed_plugins.json 2>/dev/null | grep -A5 'devflow@devflow-marketplace'
```

- **Healthy**: no devflow entry in installed_plugins.json
- **Problem**: if both the symlink AND the plugin are active, commands may conflict or shadow each other
- **Fix**: `claude plugin uninstall devflow@devflow-marketplace` or `make plugin-dev` (which handles this automatically)

### 4. Version consistency

Check that all command descriptions in `devflow-plugin/commands/*.md` have the same version badge as `Makefile`:

```bash
grep "^VERSION" Makefile
grep -h "^description:" devflow-plugin/commands/*.md | head -3
```

## Output

Report a summary table:

| Check | Status | Notes |
|-------|--------|-------|
| Commands symlink | ... | ... |
| Skills symlink | ... | ... |
| Stale plugin | ... | ... |
| Version match | ... | ... |

If everything is healthy, say so. If not, list the fix commands.
