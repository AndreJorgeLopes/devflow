---
id: ARCH-agent-spawning-consistency
title: "Agent Spawning Consistency Through Agent-Deck"
priority: P1
category: architecture
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - bin/devflow
  - lib/worktree.sh
  - lib/init.sh
  - skills/worktree-flow/new-feature.md
  - skills/worktree-flow/finish-feature.md
  - templates/CLAUDE.md.tmpl
---

# Agent Spawning Consistency Through Agent-Deck

## Context

Devflow spawns AI agents from multiple places in the codebase — the `devflow worktree` command with its `--agent` flag, direct invocations in `bin/devflow`, and potentially from init scripts. Currently these spawn points use raw `claude` or `opencode` commands directly, bypassing agent-deck entirely. This means spawned sessions are invisible to agent-deck's tracking, miss memory/observability layers (Hindsight, Langfuse), and aren't organized into groups.

Agent-deck is the session management layer (Layer 3) that provides visibility, group organization, MCP connection pooling, and lifecycle management. Every agent session MUST pass through it.

## Problem Statement

Agent spawning is inconsistent and fragmented:

1. Some spawn points call `claude` or `opencode` directly instead of going through `agent-deck add`
2. The `--agent <name>` flag on `devflow worktree` uses opt-in logic — agents should be the DEFAULT, with `--no-agent` as the opt-out
3. Spawned agents don't get assigned to the correct agent-deck group (project/features, project/bugfixes, etc.)
4. Sessions launched outside agent-deck are invisible — no tracking, no memory injection, no observability

## Desired Outcome

- **Every** agent spawn in devflow goes through `agent-deck add <path> -c <tool> -g <group>`
- `devflow worktree` launches an agent by default; the flag becomes `--no-agent` (inverse logic)
- Each launch auto-detects the correct group from the branch prefix (`feat/` → features, `fix/` → bugfixes, `chore/` → chores, etc.)
- Sessions are visible in `agent-deck list`, receive MCP connections (Hindsight), and are logged

## Implementation Guide

### Step 1: Audit all agent spawn points

Search these files for any direct invocation of `claude`, `opencode`, or any AI tool binary:

- `bin/devflow` — look for `exec`, `command`, or subprocess calls that launch an AI tool
- `lib/worktree.sh` — the `--agent` flag handling
- `lib/init.sh` — any post-init agent launch
- `skills/worktree-flow/new-feature.md` — instructions that tell the agent to spawn sub-agents
- `skills/worktree-flow/finish-feature.md` — same

Document every spawn point found.

### Step 2: Create a shared spawn function

In `lib/worktree.sh` (or a new `lib/agent.sh` if separation is cleaner), create:

```bash
# Spawns an agent through agent-deck. Never call claude/opencode directly.
# Usage: devflow_spawn_agent <worktree_path> <tool> <group>
devflow_spawn_agent() {
  local path="$1"
  local tool="${2:-claude}"
  local group="$3"

  if ! command -v agent-deck &>/dev/null; then
    echo "ERROR: agent-deck not found. Install it first." >&2
    return 1
  fi

  agent-deck add "$path" -c "$tool" ${group:+-g "$group"}
}
```

### Step 3: Invert the agent flag logic

In `lib/worktree.sh`, change:

- **Before:** `--agent <name>` opts IN to launching an agent
- **After:** Agent launch is DEFAULT. Add `--no-agent` flag that opts OUT

```bash
# Old:
#   devflow worktree feat/foo --agent claude
# New:
#   devflow worktree feat/foo              # launches agent by default
#   devflow worktree feat/foo --no-agent   # skips agent launch
```

### Step 4: Auto-detect group from branch prefix

```bash
detect_group() {
  local branch="$1"
  local project="$2"  # e.g., "messaging"

  case "$branch" in
    feat/*|feature/*) echo "${project}/features" ;;
    fix/*|bugfix/*)   echo "${project}/bugfixes" ;;
    review/*|cr/*)    echo "${project}/reviews" ;;
    chore/*|refactor/*) echo "${project}/chores" ;;
    *)                echo "${project}" ;;  # fallback to project root group
  esac
}
```

### Step 5: Replace all raw spawns

Go through every spawn point found in Step 1 and replace with calls to `devflow_spawn_agent`. Ensure every call passes the correct group.

### Step 6: Update skill documents

Update `new-feature.md` and `finish-feature.md` to reference the new default behavior and `--no-agent` flag.

## Acceptance Criteria

- [ ] `grep -r 'claude\|opencode' bin/ lib/` returns ZERO direct invocations outside of the spawn function and tool-detection logic
- [ ] `devflow worktree feat/test-branch` creates a worktree AND launches an agent-deck session without any `--agent` flag
- [ ] `devflow worktree feat/test-branch --no-agent` creates a worktree WITHOUT launching an agent
- [ ] The launched session appears in `agent-deck list` with the correct group assignment
- [ ] Branch prefix `feat/` maps to `<project>/features` group
- [ ] Branch prefix `fix/` maps to `<project>/bugfixes` group
- [ ] Skills documents (`new-feature.md`, `finish-feature.md`) reference the updated flag behavior
- [ ] A session launched through devflow has Hindsight MCP available (verify with `agent-deck inspect <session>`)

## Technical Notes

- agent-deck's `add` command syntax: `agent-deck add <path> -c <tool> [-g <group>] [-n <name>]`
- The tool flag (`-c`) should default to whatever the user configured in `devflow init` or fall back to `claude`
- If agent-deck is not installed, the command should fail loudly with an install instruction — never silently fall back to raw `claude`
- Consider storing the default tool preference in `~/.config/devflow/config.toml` or similar

## Verification

```bash
# 1. Create a test worktree with default agent
devflow worktree feat/test-spawn-001

# 2. Verify session exists in agent-deck
agent-deck list | grep "test-spawn-001"

# 3. Verify group assignment
agent-deck inspect <session-id> | grep "features"

# 4. Verify no-agent flag works
devflow worktree feat/test-spawn-002 --no-agent
agent-deck list | grep -v "test-spawn-002"  # should NOT appear

# 5. Cleanup
wt drop feat/test-spawn-001
wt drop feat/test-spawn-002
```
