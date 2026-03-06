---
id: ARCH-global-vs-per-project-configs
title: "Global vs Per-Project Configs"
priority: P1
category: architecture
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - lib/init.sh
  - ~/.devflow/checks/
  - ~/.config/worktrunk/config.toml
  - .devflow/checks/*.md
  - .worktrunk.toml
---

# Global vs Per-Project Configs

## Context

Two configuration systems — code review checks and worktrunk worktree config — are currently set up as per-project files (`.devflow/checks/*.md` and `.worktrunk.toml`). Since devflow is a GLOBAL development workflow system, these configs should ideally be global (applied to all projects) rather than duplicated in every project directory.

However, whether global configuration is supported depends on the tools themselves. This ticket requires investigation before implementation.

## Problem Statement

1. **`.devflow/checks/*.md`** — Code review rules for the `devflow check` command. Currently placed per-project. If every project needs the same rules, maintaining copies in each project is fragile and error-prone.

2. **`.worktrunk.toml`** — Worktree configuration for the `wt` command. Currently placed per-project. Global config would prevent duplication.

Both tools may or may not support global configuration. The answer determines the implementation path.

## Desired Outcome

- If the tools support global config: configs live in a single global location and apply everywhere
- If the tools don't support global config: `devflow init` creates/symlinks per-project configs with a "managed by devflow" header, sourced from a single location in the devflow repo
- Either way, there's ONE source of truth for the config content

## Implementation Guide

### Step 1: Investigate code review CLI global config

```bash
# Check devflow check help for config options
devflow check --help

# Look for global config documentation
devflow check config --help 2>/dev/null

# Check if devflow check reads from standard global locations
ls ~/.devflow/checks/ 2>/dev/null
ls ~/.config/devflow/ 2>/dev/null

# Check docs for global checks directory support
```

Key questions:

- Does `devflow check` support a `--config` or `--checks-dir` flag?
- Does the code review CLI read checks from `~/.devflow/checks/` globally?
- Is there a config file that specifies check locations?

### Step 2: Investigate worktrunk (`wt`) global config

```bash
# Check wt help for config options
wt --help
wt config --help 2>/dev/null

# Look for global config
ls ~/.config/worktrunk/ 2>/dev/null
ls ~/.worktrunk.toml 2>/dev/null

# Check if wt reads from XDG config
echo $XDG_CONFIG_HOME
```

Key questions:

- Does `wt` support a global config at `~/.config/worktrunk/config.toml`?
- Does `wt` merge global + per-project configs?
- Is there a `wt config set` command for global settings?

### Step 3A: If global config IS supported

For code review checks:

```bash
mkdir -p ~/.devflow/checks
cp /Users/andrejorgelopes/dev/devflow/templates/checks/*.md ~/.devflow/checks/
```

For worktrunk:

```bash
mkdir -p ~/.config/worktrunk
cp /Users/andrejorgelopes/dev/devflow/templates/worktrunk.toml ~/.config/worktrunk/config.toml
```

Update `lib/init.sh` to install global configs instead of per-project ones.

### Step 3B: If global config is NOT supported (fallback)

Create a single source of truth in the devflow repo and symlink to each project:

```bash
# In lib/init.sh, during devflow init:

# code review checks
DEVFLOW_CHECKS_DIR="/Users/andrejorgelopes/dev/devflow/configs/review-checks"
mkdir -p "$PROJECT_DIR/.devflow"
ln -sf "$DEVFLOW_CHECKS_DIR" "$PROJECT_DIR/.devflow/checks"

# worktrunk config
DEVFLOW_WORKTRUNK="/Users/andrejorgelopes/dev/devflow/configs/worktrunk.toml"
ln -sf "$DEVFLOW_WORKTRUNK" "$PROJECT_DIR/.worktrunk.toml"
```

Add a header comment to the source files:

```markdown
<!-- Managed by devflow. Edit at /Users/andrejorgelopes/dev/devflow/configs/review-checks/ -->
```

### Step 4: Update `devflow init`

Modify `lib/init.sh` to use whichever approach works (3A or 3B):

```bash
setup_review_checks() {
  if review_cli_supports_global; then
    install_global_review_checks
  else
    symlink_project_review_checks "$PROJECT_DIR"
  fi
}

setup_worktrunk_config() {
  if wt_supports_global; then
    install_global_worktrunk_config
  else
    symlink_project_worktrunk_config "$PROJECT_DIR"
  fi
}
```

### Step 5: Create the source-of-truth directory

```bash
mkdir -p /Users/andrejorgelopes/dev/devflow/configs/review-checks
mkdir -p /Users/andrejorgelopes/dev/devflow/configs

# Move/create the canonical check files
# Move/create the canonical worktrunk config
```

## Acceptance Criteria

- [ ] Investigation results documented: does `devflow check` support global checks directory? Does `wt` support global config?
- [ ] A single source of truth exists for code review checks (in the devflow repo)
- [ ] A single source of truth exists for worktrunk config (in the devflow repo)
- [ ] If global: configs installed globally and work across all projects without per-project files
- [ ] If per-project: symlinks point to the devflow source, not copies
- [ ] `devflow init` handles the setup automatically (global or symlink depending on tool support)
- [ ] Running `devflow check` in any devflow-initialized project uses the correct rules
- [ ] Running `wt step` in any devflow-initialized project uses the correct config
- [ ] Updating the source-of-truth file propagates to all projects (either globally or via symlinks)

## Technical Notes

- **Symlink gotcha**: Some tools don't follow symlinks for config files. If symlinks don't work, fall back to copying with a "managed by devflow" comment and a `devflow sync` command to push updates.
- **XDG Base Directory**: Many CLI tools respect `$XDG_CONFIG_HOME` (defaults to `~/.config`). Check if either tool uses XDG conventions.
- **Git and symlinks**: `.devflow/checks` symlinks in a git repo might cause issues. Add the symlink target to `.gitignore` if the link points outside the repo.
- **worktrunk vs wt**: The binary may be `worktrunk` or `wt` — check which alias is installed.
- **Code Review CLI**: The `devflow check` command wraps the code review backend — no separate CLI install needed.

## Verification

```bash
# 1. Verify source of truth exists
ls /Users/andrejorgelopes/dev/devflow/configs/review-checks/
ls /Users/andrejorgelopes/dev/devflow/configs/worktrunk.toml

# 2. Initialize a test project
cd /tmp && mkdir test-project && cd test-project && git init
devflow init

# 3. Verify checks work
devflow check  # should use devflow rules

# 4. Verify worktrunk works
wt step test-branch  # should use devflow config

# 5. Verify single source of truth
# Edit the source file, verify the change is visible in the project
echo "# test change" >> /Users/andrejorgelopes/dev/devflow/configs/review-checks/test.md
cat .devflow/checks/test.md  # should show the change (if symlinked)

# 6. Cleanup
cd / && rm -rf /tmp/test-project
```
