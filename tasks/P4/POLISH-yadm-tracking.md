---
id: POLISH-yadm-tracking
title: "YADM Tracking for All Devflow-Related Configs"
priority: P4
category: polish
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - ~/.config/zsh/init
  - ~/.config/zsh/.zshrc
  - ~/.config/zsh/shell
  - ~/.config/zsh/envs
  - ~/.config/zsh/keybinds
  - ~/.config/zsh/aliases
  - ~/.config/zsh/functions
  - ~/.claude/CLAUDE.md
  - ~/.claude/AGENTS.md
  - ~/.agent-deck/config.toml
  - ~/.hindsight/profiles/main.env
  - ~/.hindsight/profiles/metadata.json
  - ~/.hindsight/active_profile
  - ~/.config/opencode/skills/superpowers/ (all files)
  - ~/.zshenv
  - ~/dev/aircall/visualizations/README.md
  - ~/dev/aircall/visualizations/devflow-ecosystem.md
  - ~/dev/aircall/visualizations/development-workflow.md
  - ~/dev/devflow/visualizations/devflow-ecosystem.md
  - ~/dev/devflow/visualizations/development-workflow.md
---

# YADM Tracking for All Devflow-Related Configs

## Context

The developer uses [yadm](https://yadm.io/) for dotfile management across machines. Currently yadm tracks 0 files — none of the devflow-related configuration files are version-controlled. This means:

- Losing the machine or reinstalling means manually recreating all agent configs, shell integrations, skill files, and Hindsight profiles
- No history of changes to critical files like `CLAUDE.md` or `AGENTS.md`
- No way to sync configs across machines

Additionally, some devflow visualizations currently live in `~/dev/aircall/visualizations/` but logically belong in the devflow project repository. These should be moved to `~/dev/devflow/visualizations/` and symlinked back.

## Problem Statement

1. **No dotfile tracking**: Critical devflow configs (shell init, agent instructions, skills, Hindsight profiles) are not tracked by yadm
2. **Scattered visualizations**: Devflow architecture diagrams live in the aircall project's visualizations directory instead of the devflow repo
3. **Numbered prefixes**: Visualization files have numbered prefixes (`10-devflow-ecosystem.md`, `11-development-workflow.md`) that are vestiges of the aircall project's naming scheme — already renamed to clean names but need to be moved to proper home
4. **devflow repo gaps**: The devflow git repo may not track `devflow-plugin/`, `tasks/`, or `visualizations/` directories

## Desired Outcome

- All devflow-related dotfiles tracked by yadm with a clean initial commit
- Visualizations live in `~/dev/devflow/visualizations/` (canonical location)
- Symlinks from `~/dev/aircall/visualizations/devflow/` point to the canonical files
- The aircall visualizations README updated to reference new paths
- The devflow git repo tracks all generated/managed directories

## Implementation Guide

### Part 1: Add Files to YADM

#### Step 1: Verify files exist

```bash
# Check each file exists before adding
ls -la ~/.config/zsh/init
ls -la ~/.config/zsh/.zshrc
ls -la ~/.config/zsh/shell
ls -la ~/.config/zsh/envs
ls -la ~/.config/zsh/keybinds
ls -la ~/.config/zsh/aliases
ls -la ~/.config/zsh/functions
ls -la ~/.claude/CLAUDE.md
ls -la ~/.claude/AGENTS.md
ls -la ~/.agent-deck/config.toml
ls -la ~/.hindsight/profiles/main.env
ls -la ~/.hindsight/profiles/metadata.json
ls -la ~/.hindsight/active_profile
ls -la ~/.config/opencode/skills/superpowers/
ls -la ~/.zshenv
```

#### Step 2: Add shell config files

```bash
yadm add ~/.zshenv
yadm add ~/.config/zsh/init
yadm add ~/.config/zsh/.zshrc
yadm add ~/.config/zsh/shell
yadm add ~/.config/zsh/envs
yadm add ~/.config/zsh/keybinds
yadm add ~/.config/zsh/aliases
yadm add ~/.config/zsh/functions
```

#### Step 3: Add agent config files

```bash
yadm add ~/.claude/CLAUDE.md
yadm add ~/.claude/AGENTS.md
yadm add ~/.agent-deck/config.toml
```

#### Step 4: Add Hindsight profile (NOT logs)

```bash
yadm add ~/.hindsight/profiles/main.env
yadm add ~/.hindsight/profiles/metadata.json
yadm add ~/.hindsight/active_profile
```

**IMPORTANT**: Do NOT add `~/.hindsight/profiles/main.log` or any log/data files. Only configuration and profile metadata.

#### Step 5: Add OpenCode skills

```bash
# Add all superpowers skill files
yadm add ~/.config/opencode/skills/superpowers/
```

#### Step 6: Commit to yadm

```bash
yadm status  # Review what's staged
yadm commit -m "feat: track devflow-related dotfiles

Adds shell config, agent instructions, Hindsight profiles,
Agent Deck config, and OpenCode superpowers skills to yadm."
```

### Part 2: Move Visualizations to Devflow Repo

#### Step 7: Create devflow visualizations directory

```bash
mkdir -p ~/dev/devflow/visualizations
```

#### Step 8: Move files (they already have clean names)

```bash
# Move from aircall visualizations to devflow repo
mv ~/dev/aircall/visualizations/devflow-ecosystem.md ~/dev/devflow/visualizations/devflow-ecosystem.md
mv ~/dev/aircall/visualizations/development-workflow.md ~/dev/devflow/visualizations/development-workflow.md
```

#### Step 9: Create symlink directory in aircall visualizations

```bash
mkdir -p ~/dev/aircall/visualizations/devflow
```

#### Step 10: Create symlinks

```bash
ln -s ~/dev/devflow/visualizations/devflow-ecosystem.md ~/dev/aircall/visualizations/devflow/devflow-ecosystem.md
ln -s ~/dev/devflow/visualizations/development-workflow.md ~/dev/aircall/visualizations/devflow/development-workflow.md
```

#### Step 11: Verify symlinks work

```bash
ls -la ~/dev/aircall/visualizations/devflow/
# Should show symlinks pointing to ~/dev/devflow/visualizations/
cat ~/dev/aircall/visualizations/devflow/devflow-ecosystem.md | head -5
# Should show content
```

#### Step 12: Update aircall visualizations README

Edit `~/dev/aircall/visualizations/README.md` to reference the new paths:

- Note that devflow visualizations now live in the devflow repo
- Reference `devflow/devflow-ecosystem.md` and `devflow/development-workflow.md` (symlinked)

### Part 3: Ensure Devflow Repo Tracks All Directories

#### Step 13: Add directories to devflow git

```bash
cd ~/dev/devflow

# Check what's currently tracked
git status

# Add new directories
git add visualizations/
git add tasks/

# Check if devflow-plugin exists and add it
ls devflow-plugin/ && git add devflow-plugin/ || echo "devflow-plugin/ not found, skip"

git commit -m "feat: track visualizations, tasks, and generated plugin directories"
```

## Acceptance Criteria

- [ ] `yadm list` shows all files from the list above
- [ ] `yadm status` is clean (all files committed)
- [ ] `~/.hindsight/profiles/main.log` is NOT tracked by yadm
- [ ] `~/dev/devflow/visualizations/devflow-ecosystem.md` exists (not a symlink — canonical file)
- [ ] `~/dev/devflow/visualizations/development-workflow.md` exists (not a symlink — canonical file)
- [ ] `~/dev/aircall/visualizations/devflow/devflow-ecosystem.md` is a symlink to `~/dev/devflow/visualizations/devflow-ecosystem.md`
- [ ] `~/dev/aircall/visualizations/devflow/development-workflow.md` is a symlink to `~/dev/devflow/visualizations/development-workflow.md`
- [ ] `~/dev/aircall/visualizations/README.md` references the new devflow/ subdirectory
- [ ] `~/dev/devflow/` git repo tracks `visualizations/`, `tasks/` directories
- [ ] Original visualization files no longer exist at old paths (moved, not copied)

## Technical Notes

- **yadm** is a wrapper around git that uses `~` as the work tree. `yadm add` / `yadm commit` work like regular git commands.
- **yadm vs git**: yadm tracks user-scoped dotfiles. The devflow project repo (regular git) tracks project files. These are separate concerns.
- **Hindsight main.env**: Contains environment variables like LLM provider config. Safe to track. `main.log` contains memory data — do NOT track.
- **OpenCode skills**: The `~/.config/opencode/skills/superpowers/` directory contains SKILL.md files and bundled resources. All should be tracked since they're hand-authored.
- **Symlink direction**: The canonical file lives in `~/dev/devflow/visualizations/`. The symlink lives in `~/dev/aircall/visualizations/devflow/`. This means edits in either location update the same file.
- **No secrets**: None of the files listed contain secrets. `main.env` has LLM provider names (like `claude-code`) but no API keys — those come from environment variables.

## Verification

```bash
# Verify yadm tracking
yadm list | grep -E "(zsh|claude|agent-deck|hindsight|opencode|zshenv)" | wc -l
# Should be >= 15 files

# Verify no logs tracked
yadm list | grep "main.log"
# Should return nothing

# Verify symlinks
file ~/dev/aircall/visualizations/devflow/devflow-ecosystem.md
# Should say "symbolic link to ..."

# Verify devflow repo
cd ~/dev/devflow && git ls-files visualizations/
# Should list the two visualization files

# Verify content accessible via symlink
diff ~/dev/devflow/visualizations/devflow-ecosystem.md ~/dev/aircall/visualizations/devflow/devflow-ecosystem.md
# Should show no differences
```
