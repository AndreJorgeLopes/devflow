---
id: ARCH-skills-registry-global-sources
title: "Skills Registry to Global Sources + MCP Pool"
priority: P1
category: architecture
status: open
depends_on:
  - ARCH-update-actual-configs
estimated_effort: M
files_to_touch:
  - ~/.agent-deck/config.toml
  - ~/.agent-deck/skills/sources.toml
  - lib/init.sh
  - devflow-plugin/skills/**
---

# Skills Registry to Global Sources + MCP Pool

## Context

Agent-deck has a dedicated skills registry system that discovers skills from "global sources" — not from `config.toml` and not from per-project `.claude/skills/` directories. Skills are discovered from registered source directories and can be attached to projects via managed manifests. The current devflow implementation may be placing skills in the wrong locations, making them invisible to agent-deck's registry.

Agent-deck's skill discovery model:

- **Global source registry**: `~/.agent-deck/skills/sources.toml` — lists directories where agent-deck looks for skills
- **Default sources**: `pool` → `~/.agent-deck/skills/pool`, `claude-global` → `~/.claude/skills`
- **Project attachment**: `<project>/.agent-deck/skills.toml` — a managed manifest that references global skills

Skills should NEVER be copied into per-project directories. They should live in global registries and be referenced by projects.

## Problem Statement

1. Devflow skills may not be registered as a global source in agent-deck
2. Skills might be getting copied to project `.claude/skills/` directories instead of being globally available
3. The MCP pool (which enables shared MCP connections across sessions) may not be properly configured
4. `lib/init.sh` may be copying skills to project directories instead of registering global sources

## Desired Outcome

- Devflow skills are registered as a global source in agent-deck's skill registry
- Agent-deck discovers devflow skills automatically for all sessions
- Skills are NEVER copied to per-project directories — only global registries
- MCP pool is enabled and configured for connection sharing across sessions
- `devflow init` registers the skill source (idempotently), never copies skills

## Implementation Guide

### Step 1: Verify agent-deck skill registry structure

Check what currently exists:

```bash
# Check if sources.toml exists
cat ~/.agent-deck/skills/sources.toml 2>/dev/null || echo "Not found"

# Check the pool directory
ls ~/.agent-deck/skills/pool/ 2>/dev/null || echo "Not found"

# Check registered sources
agent-deck skill source list 2>/dev/null || echo "Command not available"
```

### Step 2: Register devflow skills as a global source

The devflow plugin's skills directory should be registered as a source:

```bash
# Register the devflow skills source
agent-deck skill source add devflow /Users/andrejorgelopes/dev/devflow/devflow-plugin/skills
```

If the CLI command doesn't exist, manually create/update `~/.agent-deck/skills/sources.toml`:

```toml
[sources.devflow]
path = "/Users/andrejorgelopes/dev/devflow/devflow-plugin/skills"
type = "directory"
auto_discover = true
```

### Step 3: Symlink to the pool directory (belt and suspenders)

As a fallback for discovery, also symlink individual skills to the pool:

```bash
mkdir -p ~/.agent-deck/skills/pool
for skill_dir in /Users/andrejorgelopes/dev/devflow/devflow-plugin/skills/*/; do
  skill_name=$(basename "$skill_dir")
  ln -sf "$skill_dir" ~/.agent-deck/skills/pool/"$skill_name"
done
```

### Step 4: Remove any per-project skill copies

Search for and remove any devflow skills that were copied to project directories:

```bash
# Find any project-level skill copies
find ~/dev -path "*/.claude/skills/*" -name "*.md" | head -20

# Remove devflow-managed skills from project directories
# (Be careful — only remove devflow skills, not project-specific ones)
```

### Step 5: Update `lib/init.sh`

Find the skill installation code in `lib/init.sh` and replace it:

**Before** (copying skills):

```bash
# DON'T DO THIS
cp -r skills/ "$PROJECT_DIR/.claude/skills/"
```

**After** (registering global source):

```bash
# Register devflow skills as global source (idempotent)
if ! agent-deck skill source list 2>/dev/null | grep -q "devflow"; then
  agent-deck skill source add devflow "$DEVFLOW_DIR/devflow-plugin/skills"
fi

# Attach skills to project if needed
# agent-deck skill attach <project> <skill-name>
```

### Step 6: Enable MCP Pool

Ensure `~/.agent-deck/config.toml` has the MCP pool configuration:

```toml
[mcp_pool]
enabled = true
auto_start = true
pool_all = true
exclude_mcps = []
fallback_to_stdio = true
show_pool_status = true
```

This enables:

- **Connection pooling**: MCP servers (like Hindsight) are shared across sessions instead of each session starting its own
- **Auto-start**: Pool starts when agent-deck starts
- **Pool all**: All configured MCPs are pooled by default
- **Fallback**: If pooling fails, sessions fall back to direct stdio connections

## Acceptance Criteria

- [ ] `agent-deck skill source list` (or equivalent) shows "devflow" as a registered source
- [ ] `~/.agent-deck/skills/sources.toml` exists and contains the devflow source entry
- [ ] Skills in `devflow-plugin/skills/` are discoverable by agent-deck without any per-project copies
- [ ] `find ~/dev -path "*/.claude/skills/devflow*"` returns NO results (no per-project copies)
- [ ] `lib/init.sh` registers the global source, does NOT copy skills to project directories
- [ ] `[mcp_pool]` section in `~/.agent-deck/config.toml` has `enabled = true` and `pool_all = true`
- [ ] Running `agent-deck skill list` shows devflow skills available
- [ ] `devflow init` can be run multiple times without creating duplicate source registrations (idempotent)

## Technical Notes

- Agent-deck's skill source system may vary by version. Check `agent-deck --version` and `agent-deck help skill` for exact syntax.
- The `sources.toml` file format may differ from what's documented above — inspect any existing file first and match its format.
- MCP pool requires agent-deck to be running as a daemon/service. Verify with `agent-deck status` or `agent-deck pool status`.
- Symlinks in the pool directory should point to DIRECTORIES (one per skill), not individual `.md` files.
- The `auto_discover = true` flag means agent-deck will watch the source directory for new skills — no manual refresh needed.
- If skills have a `SKILL.md` or `skill.toml` manifest file, ensure the devflow skills follow that convention.

## Verification

```bash
# 1. Verify source registration
agent-deck skill source list
# Expected: "devflow" source listed pointing to devflow-plugin/skills

# 2. Verify skill discovery
agent-deck skill list | grep -i "devflow\|worktree\|process"
# Expected: devflow skills visible

# 3. Verify no per-project copies
find ~/dev -path "*/.claude/skills/*" -name "*.md" -exec grep -l "devflow" {} \;
# Expected: no results

# 4. Verify MCP pool
agent-deck pool status 2>/dev/null || agent-deck status
# Expected: pool running, MCPs listed

# 5. Verify idempotency
devflow init && devflow init  # run twice
agent-deck skill source list | grep -c "devflow"
# Expected: exactly 1
```
