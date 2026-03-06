---
id: FEAT-lazygit-lazydocker-wrappers
title: "Lazygit and Lazydocker CLI Wrappers"
priority: P2
category: features
status: open
depends_on: []
estimated_effort: S
files_to_touch:
  - bin/devflow
  - lib/wrappers.sh
---

# Lazygit and Lazydocker CLI Wrappers

## Context

Developers frequently need to visually inspect git state (branches, diffs, stash, log) and Docker container health (logs, stats, restart) during development sessions. `lazygit` and `lazydocker` are excellent TUI tools for this, but they require separate invocation and aren't integrated into the devflow CLI. Simple wrappers with install-on-demand bring these tools into the devflow surface area.

## Problem Statement

1. Developers context-switch between `devflow` commands and standalone `lazygit`/`lazydocker` invocations
2. New team members may not have these tools installed, leading to friction when they're recommended
3. There's no standardized way to launch these tools in the context of the current worktree or devflow project

## Desired Outcome

- `devflow git` launches `lazygit` in the current directory (or active worktree)
- `devflow docker` launches `lazydocker`
- If either tool is not installed, devflow offers to install it via `brew install`
- Both are simple passthrough wrappers — no additional logic beyond install-on-demand

## Implementation Guide

### Step 1: Create `lib/wrappers.sh`

```bash
#!/usr/bin/env bash

# Ensure a TUI tool is installed, offering to install via brew if missing.
# Usage: ensure_tool <tool-name>
# Returns: 0 if tool is available, 1 if user declined install
ensure_tool() {
  local tool="$1"

  if command -v "$tool" &>/dev/null; then
    return 0
  fi

  echo "${tool} is not installed."

  if command -v brew &>/dev/null; then
    read -r -p "Install ${tool} via brew? [Y/n] " response
    case "$response" in
      [nN]*)
        echo "Skipping. Install manually: brew install ${tool}"
        return 1
        ;;
      *)
        echo "Installing ${tool}..."
        brew install "$tool"
        if command -v "$tool" &>/dev/null; then
          echo "${tool} installed successfully."
          return 0
        else
          echo "ERROR: Installation failed. Try manually: brew install ${tool}" >&2
          return 1
        fi
        ;;
    esac
  else
    echo "Homebrew not found. Install ${tool} manually:"
    echo "  brew install ${tool}"
    echo "  or see: https://github.com/jesseduffield/${tool}"
    return 1
  fi
}

# Launch lazygit in the specified directory (default: current dir)
devflow_git() {
  local dir="${1:-.}"

  if ! ensure_tool "lazygit"; then
    return 1
  fi

  lazygit -p "$dir"
}

# Launch lazydocker
devflow_docker() {
  if ! ensure_tool "lazydocker"; then
    return 1
  fi

  lazydocker
}
```

### Step 2: Add commands to `bin/devflow`

In the main `bin/devflow` script, add cases for the `git` and `docker` subcommands:

```bash
# In the case statement for subcommands:
git)
  source "${DEVFLOW_LIB}/wrappers.sh"
  devflow_git "${2:-.}"
  ;;
docker)
  source "${DEVFLOW_LIB}/wrappers.sh"
  devflow_docker
  ;;
```

### Step 3: Add help text

Update the help/usage output to include:

```
  devflow git              Launch lazygit in current directory
  devflow git <path>       Launch lazygit in specified directory
  devflow docker           Launch lazydocker
```

### Step 4: Worktree integration (optional enhancement)

If the user is in a devflow-managed worktree, `devflow git` should automatically detect the worktree root and launch lazygit there:

```bash
devflow_git() {
  local dir="${1:-}"

  # Auto-detect worktree root if no dir specified
  if [[ -z "$dir" ]]; then
    dir=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
  fi

  if ! ensure_tool "lazygit"; then
    return 1
  fi

  lazygit -p "$dir"
}
```

## Acceptance Criteria

- [ ] `devflow git` launches `lazygit` in the current directory
- [ ] `devflow git <path>` launches `lazygit` in the specified directory
- [ ] `devflow docker` launches `lazydocker`
- [ ] If `lazygit` is not installed, the user is prompted: "Install lazygit via brew? [Y/n]"
- [ ] If `lazydocker` is not installed, the user is prompted: "Install lazydocker via brew? [Y/n]"
- [ ] Answering 'Y' installs the tool via `brew install` and then launches it
- [ ] Answering 'n' skips with a helpful message showing manual install instructions
- [ ] If brew is not available, a manual install instruction is shown (no crash)
- [ ] `devflow help` or `devflow --help` lists the `git` and `docker` commands
- [ ] Both commands work from any directory, not just devflow project roots

## Technical Notes

- `lazygit -p <path>` opens lazygit in the specified path — verify this flag exists in the installed version
- `lazydocker` doesn't take a path argument — it connects to the Docker daemon regardless of working directory
- Both tools are TUI applications that take over the terminal — they block until the user exits (this is expected)
- `brew install` may require user confirmation for Xcode CLI tools on fresh macOS installs
- Consider also supporting `nix`, `apt`, or `pacman` for non-macOS users in a future iteration, but brew-only is fine for now
- The `devflow git` command name shadows the actual `git` command — this is intentional (it's namespaced under `devflow`), but document it clearly so users don't confuse `devflow git` with `git`

## Verification

```bash
# 1. Test lazygit wrapper (assuming lazygit is installed)
devflow git
# Expect: lazygit opens in current directory

# 2. Test with path argument
devflow git ~/dev/other-project
# Expect: lazygit opens in specified directory

# 3. Test lazydocker wrapper
devflow docker
# Expect: lazydocker opens

# 4. Test install-on-demand (simulate missing tool)
# Temporarily: sudo mv $(which lazygit) /tmp/lazygit-backup
devflow git
# Expect: "lazygit is not installed. Install lazygit via brew? [Y/n]"
# Answer Y → installs and launches
# Restore: sudo mv /tmp/lazygit-backup $(which lazygit)

# 5. Test install decline
# (With tool uninstalled)
devflow git
# Answer 'n'
# Expect: "Skipping. Install manually: brew install lazygit"

# 6. Test help output
devflow help | grep -E "git|docker"
# Expect: both commands listed with descriptions
```
