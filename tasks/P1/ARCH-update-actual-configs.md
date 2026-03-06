---
id: ARCH-update-actual-configs
title: "Update Actual Configs (Not Just Templates)"
priority: P1
category: architecture
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - ~/.agent-deck/config.toml
  - ~/.claude/CLAUDE.md
  - templates/config.toml.tmpl
  - templates/CLAUDE.md.tmpl
---

# Update Actual Configs (Not Just Templates)

## Context

The previous implementation round focused on updating template files (`templates/config.toml.tmpl`, `templates/CLAUDE.md.tmpl`) but never applied those changes to the ACTUAL running configuration files on this machine. Templates are useless if the live configs don't match — agent-deck reads `~/.agent-deck/config.toml`, not the template, and Claude Code reads `~/.claude/CLAUDE.md`, not the template.

This machine is the primary development environment. The configs need to be correct NOW, not just for future `devflow init` runs.

## Problem Statement

1. **`~/.agent-deck/config.toml`** (the live config) may have incorrect syntax or missing sections compared to the updated template. Known issues from the template rewrite include: correct `[tools.*]` format, `[mcps.*]` sections, `[docker]` with `mount_ssh = true`, `[worktree]` section, `[claude]` section, `[mcp_pool]` with `enabled = true` and `pool_all = true`.

2. **`~/.claude/CLAUDE.md`** (the live user-scoped CLAUDE.md) may be missing the "Starting Feature Work" section and other updates that were added to the template.

3. There's no verification that the actual configs match the templates — drift is invisible.

## Desired Outcome

- `~/.agent-deck/config.toml` is updated with all fixes from the template rewrite
- `~/.claude/CLAUDE.md` is updated with all additions from the template
- A diff confirms the actual configs match the templates (with expected project-specific differences)
- Future `devflow init` runs won't overwrite manual customizations (templates should be additive, not destructive)

## Implementation Guide

### Step 1: Read the current actual configs

Read both files to understand their current state:

```bash
cat ~/.agent-deck/config.toml
cat ~/.claude/CLAUDE.md
```

### Step 2: Read the templates

Read the updated templates to understand what changes need to be applied:

```bash
cat templates/config.toml.tmpl
cat templates/CLAUDE.md.tmpl
```

### Step 3: Diff and identify gaps

For each config, identify:

- Sections present in template but missing in actual config
- Sections present in actual config but with incorrect syntax
- Sections present in actual config that should NOT be overwritten (custom project-specific settings)

### Step 4: Update `~/.agent-deck/config.toml`

Apply changes carefully. The following sections MUST be correct:

```toml
[tools.claude]
command = "claude"
args = []

[tools.opencode]
command = "opencode"
args = []

[mcps.hindsight]
command = "hindsight"
transport = "stdio"

[docker]
enabled = false
mount_ssh = true

[worktree]
auto_detect = true
isolation = true

[claude]
model = "claude-sonnet-4-20250514"

[mcp_pool]
enabled = true
auto_start = true
pool_all = true
exclude_mcps = []
fallback_to_stdio = true
show_pool_status = true
```

Preserve any existing sections that are correct and not covered by the template.

### Step 5: Update `~/.claude/CLAUDE.md`

Add the "Starting Feature Work" section if missing. Ensure the devflow instructions block is present and up to date. Do NOT overwrite non-devflow content in the file — CLAUDE.md may contain other project instructions.

Look for markers like `<!-- devflow -->` and `<!-- /devflow -->` to identify the devflow-managed section. Only update content within those markers.

### Step 6: Verify consistency

```bash
# For config.toml — diff template placeholders vs actual values
diff <(sed 's/{{[^}]*}}/PLACEHOLDER/g' templates/config.toml.tmpl) \
     <(cat ~/.agent-deck/config.toml)

# For CLAUDE.md — check devflow section matches
grep -A 100 "<!-- devflow -->" ~/.claude/CLAUDE.md
grep -A 100 "<!-- devflow -->" templates/CLAUDE.md.tmpl
```

## Acceptance Criteria

- [ ] `~/.agent-deck/config.toml` contains all required sections: `[tools.*]`, `[mcps.*]`, `[docker]`, `[worktree]`, `[claude]`, `[mcp_pool]`
- [ ] `[mcp_pool]` has `enabled = true` and `pool_all = true`
- [ ] `[docker]` has `mount_ssh = true`
- [ ] `[mcps.hindsight]` is configured with correct command and transport
- [ ] `~/.claude/CLAUDE.md` contains the "Starting Feature Work" section within the devflow markers
- [ ] agent-deck can parse the config without errors: `agent-deck config validate` (or `agent-deck list` doesn't error)
- [ ] A diff between templates and actual configs shows only expected differences (project-specific values vs placeholders)
- [ ] No content outside the `<!-- devflow -->` markers in CLAUDE.md was modified

## Technical Notes

- **BACKUP FIRST**: Before modifying either config, create backups:
  ```bash
  cp ~/.agent-deck/config.toml ~/.agent-deck/config.toml.bak.$(date +%s)
  cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak.$(date +%s)
  ```
- The `config.toml` template uses `{{placeholder}}` syntax for variable substitution. The actual config will have real values instead.
- `~/.claude/CLAUDE.md` is read by Claude Code on every session start. Syntax errors or corruption will affect ALL Claude Code sessions.
- agent-deck may cache its config — after updating, restart any running agent-deck processes or run `agent-deck config reload` if available.
- The TOML spec requires that `[section.subsection]` syntax is used for nested tables (e.g., `[tools.claude]`), NOT `[tools] claude = ...`. Verify the actual config uses correct TOML syntax.

## Verification

```bash
# 1. Validate agent-deck config loads without errors
agent-deck list 2>&1 | grep -i "error\|invalid\|parse"
# Expected: no errors

# 2. Verify MCP pool is enabled
grep -A 3 "mcp_pool" ~/.agent-deck/config.toml
# Expected: enabled = true, pool_all = true

# 3. Verify CLAUDE.md has devflow section
grep "Starting Feature Work\|devflow" ~/.claude/CLAUDE.md
# Expected: section found

# 4. Verify backups exist
ls ~/.agent-deck/config.toml.bak.*
ls ~/.claude/CLAUDE.md.bak.*
# Expected: backup files present
```
