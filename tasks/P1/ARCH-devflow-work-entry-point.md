---
id: ARCH-devflow-work-entry-point
title: "Development Workflow Entry Point (devflow work)"
priority: P1
category: architecture
status: open
depends_on:
  - ARCH-agent-spawning-consistency
  - ARCH-forgotten-items-previous-impl
estimated_effort: L
files_to_touch:
  - lib/work.sh
  - bin/devflow
---

# Development Workflow Entry Point (`devflow work`)

## Context

Devflow currently has `devflow init` for one-time project setup but lacks a daily-driver command for starting feature work. Developers need a single command that creates an isolated worktree, launches an AI agent session through agent-deck, assigns it to the correct group, and bootstraps the session with context — all in one step.

This is the most frequently used command in the devflow workflow. It must be fast, reliable, and ergonomic.

### `devflow init` vs `devflow work` — clear separation:

| Aspect            | `devflow init`                                                     | `devflow work`                               |
| ----------------- | ------------------------------------------------------------------ | -------------------------------------------- |
| **Frequency**     | Once per project                                                   | Every feature/task                           |
| **Purpose**       | Install tools, configure CLAUDE.md, create groups, install plugins | Create worktree, launch agent, start working |
| **Scope**         | Project-level setup                                                | Branch-level work session                    |
| **Prerequisites** | None                                                               | `devflow init` already run                   |

## Problem Statement

Starting a new feature currently requires multiple manual steps:

1. `wt step -c feat/MES-1234` — create worktree with copy-ignored
2. `agent-deck add <path> -c claude -g <project>/features` — create session
3. Navigate to the session or open it
4. Manually tell the agent what to work on

This should be ONE command.

## Desired Outcome

`devflow work feat/MES-1234` does everything: creates worktree, launches tracked agent session in the correct group, and seeds it with initial context. The developer goes from "I have a ticket" to "agent is working on it" in one command.

## Implementation Guide

### Step 1: Create `lib/work.sh`

```bash
#!/usr/bin/env bash
# devflow work — primary entry point for starting feature work

set -euo pipefail

DEVFLOW_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
source "$DEVFLOW_DIR/lib/utils.sh"  # shared utilities

# Defaults
DEFAULT_TOOL="claude"
NO_AGENT=false
TOOL="$DEFAULT_TOOL"
GROUP=""
INITIAL_MESSAGE=""

usage() {
  cat <<EOF
Usage: devflow work <branch-name> [options]

Start a new work session: creates worktree, launches agent, assigns to group.

Arguments:
  <branch-name>    Branch name or ticket ID. Examples:
                   feat/MES-1234        → creates feat/MES-1234 branch
                   MES-1234             → auto-prefixed to feat/MES-1234
                   fix/MES-5678         → creates fix/MES-5678 branch

Options:
  --no-agent       Create worktree without launching an agent
  --tool <name>    AI tool to use (default: claude). Options: claude, opencode
  --group <name>   Override auto-detected group
  --message <msg>  Custom initial message for the agent
  -h, --help       Show this help

Examples:
  devflow work feat/MES-1234
  devflow work MES-1234                          # auto-prefixed to feat/
  devflow work fix/MES-5678 --tool opencode
  devflow work feat/MES-1234 --no-agent
  devflow work feat/MES-1234 --message "Focus on the API layer only"
EOF
}

# Parse the branch name and auto-prefix if needed
normalize_branch() {
  local input="$1"
  case "$input" in
    feat/*|feature/*|fix/*|bugfix/*|chore/*|refactor/*|review/*|cr/*)
      echo "$input"
      ;;
    *)
      # Auto-prefix with feat/ if no recognized prefix
      echo "feat/$input"
      ;;
  esac
}

# Detect the agent-deck group from branch prefix
detect_group() {
  local branch="$1"
  local project
  project="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"

  case "$branch" in
    feat/*|feature/*)    echo "${project}/features" ;;
    fix/*|bugfix/*)      echo "${project}/bugfixes" ;;
    review/*|cr/*)       echo "${project}/reviews" ;;
    chore/*|refactor/*)  echo "${project}/chores" ;;
    *)                   echo "${project}" ;;
  esac
}

# Generate the initial agent message
generate_initial_message() {
  local branch="$1"
  local project="$2"
  local custom_msg="$3"

  if [[ -n "$custom_msg" ]]; then
    echo "$custom_msg"
  else
    cat <<MSG
Starting work on branch: $branch
Project: $project
Recall relevant context for this task.
MSG
  fi
}

main() {
  # Parse arguments
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  local branch_input="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-agent)    NO_AGENT=true; shift ;;
      --tool)        TOOL="$2"; shift 2 ;;
      --group)       GROUP="$2"; shift 2 ;;
      --message)     INITIAL_MESSAGE="$2"; shift 2 ;;
      -h|--help)     usage; exit 0 ;;
      *)             echo "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  # Normalize the branch name
  local branch
  branch="$(normalize_branch "$branch_input")"

  local project
  project="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"

  echo "→ Starting work session: $branch"

  # Step 1: Create worktree
  echo "→ Creating worktree..."
  wt step -c "$branch"
  local worktree_path
  worktree_path="$(wt path "$branch" 2>/dev/null || git worktree list | grep "$branch" | awk '{print $1}')"

  if [[ -z "$worktree_path" ]]; then
    echo "ERROR: Could not determine worktree path for $branch" >&2
    exit 1
  fi

  echo "  Worktree created at: $worktree_path"

  # Step 2: Launch agent (unless --no-agent)
  if [[ "$NO_AGENT" == "true" ]]; then
    echo "→ Skipping agent launch (--no-agent)"
    echo ""
    echo "Worktree ready at: $worktree_path"
    echo "To launch an agent later: agent-deck add $worktree_path -c $TOOL"
    return 0
  fi

  # Detect group
  local group="${GROUP:-$(detect_group "$branch")}"

  echo "→ Launching agent session..."
  echo "  Tool: $TOOL"
  echo "  Group: $group"

  # Launch through agent-deck
  agent-deck add "$worktree_path" -c "$TOOL" -g "$group"

  # Step 3: Send initial message (if supported)
  local msg
  msg="$(generate_initial_message "$branch" "$project" "$INITIAL_MESSAGE")"

  echo ""
  echo "Session started. Initial context:"
  echo "  $msg"
  echo ""
  echo "Use 'agent-deck list' to see active sessions."
  echo "Use 'devflow done $branch' when finished."
}

main "$@"
```

### Step 2: Register in `bin/devflow`

Add the `work` subcommand to the main devflow dispatcher:

```bash
# In bin/devflow, in the case statement:
work)
  shift
  source "$DEVFLOW_DIR/lib/work.sh"
  main "$@"
  ;;
```

Also update the help text to list `work` as a command:

```
Commands:
  init          One-time project setup
  work          Start a new work session (create worktree + launch agent)
  done          Finish a work session (cleanup + PR)
  ...
```

### Step 3: Handle edge cases

1. **Branch already exists**: If the worktree/branch already exists, `wt step` will fail. Detect this and offer to hop to the existing worktree instead:

   ```bash
   if wt list | grep -q "$branch"; then
     echo "Worktree for $branch already exists. Hopping to it..."
     wt hop "$branch"
     # Still launch agent if needed
   fi
   ```

2. **Agent-deck not running**: If agent-deck is not running, start it or give a clear error:

   ```bash
   if ! agent-deck status &>/dev/null; then
     echo "Starting agent-deck..."
     agent-deck start
   fi
   ```

3. **Not in a git repo**: Fail early with a clear message if not in a git repository.

4. **devflow init not run**: Check for devflow initialization markers and suggest running `devflow init` first.

### Step 4: Auto-detection heuristics

For ticket-ID-only input (e.g., `devflow work MES-1234`):

- Default prefix is `feat/`
- Could be configurable in project config: `default_branch_prefix = "feat/"`
- Consider looking up the ticket type from Jira/Linear to auto-detect fix vs feat (future enhancement)

## Acceptance Criteria

- [ ] `devflow work feat/MES-1234` creates a worktree AND launches an agent-deck session
- [ ] `devflow work MES-1234` auto-prefixes to `feat/MES-1234`
- [ ] `devflow work fix/MES-5678` correctly assigns to `<project>/bugfixes` group
- [ ] `devflow work feat/MES-1234 --no-agent` creates worktree only, no agent
- [ ] `devflow work feat/MES-1234 --tool opencode` launches with opencode instead of claude
- [ ] `devflow work feat/MES-1234 --group custom/group` overrides auto-detected group
- [ ] `devflow work feat/MES-1234 --message "Focus on tests"` passes custom message
- [ ] Running `devflow work` with no arguments shows help
- [ ] If branch worktree already exists, the command hops to it instead of erroring
- [ ] Session appears in `agent-deck list` with correct group and path
- [ ] `bin/devflow --help` lists the `work` command with a description

## Technical Notes

- `wt step -c` creates a worktree AND copies gitignored files (node_modules, .env, etc.) — this is critical for the worktree to be immediately functional
- `wt path <branch>` may not exist in all worktrunk versions — fall back to parsing `git worktree list`
- agent-deck's `add` command syntax may accept the initial message — check `agent-deck help add`. If not, the message may need to be sent via `agent-deck send <session> <message>` or `agent-deck exec <session> -- echo <message>`
- The `detect_group` function assumes the project name is the git root directory name. This may not match the agent-deck project name if it was configured differently during `devflow init`.
- Consider storing the project name mapping in `.devflow/config.toml` or deriving from `agent-deck project list`

## Verification

```bash
# 1. Basic work session
devflow work feat/test-work-001
agent-deck list | grep "test-work-001"
# Expected: session visible in features group

# 2. Auto-prefix
devflow work TEST-002
git worktree list | grep "feat/TEST-002"
# Expected: branch auto-prefixed

# 3. No-agent mode
devflow work feat/test-work-003 --no-agent
agent-deck list | grep -v "test-work-003"
git worktree list | grep "test-work-003"
# Expected: worktree exists, no session

# 4. Custom tool
devflow work feat/test-work-004 --tool opencode
agent-deck inspect <session> | grep "opencode"
# Expected: session uses opencode

# 5. Cleanup
for b in feat/test-work-001 feat/TEST-002 feat/test-work-003 feat/test-work-004; do
  wt drop "$b" 2>/dev/null
done
```
