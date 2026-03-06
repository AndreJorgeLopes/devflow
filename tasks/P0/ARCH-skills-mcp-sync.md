---
id: ARCH-skills-mcp-sync
title: "Single Source of Truth Sync for Skills, MCPs, and Config Across All Layers"
priority: P0
category: architecture
status: open
depends_on: [ARCH-update-actual-configs, ARCH-skills-registry-global-sources]
estimated_effort: XL
files_to_touch:
  - lib/sync.sh (new)
  - bin/devflow
  - lib/init.sh
  - lib/services.sh
  - lib/check.sh
  - config/agent-deck/config.toml.tmpl
  - config/worktrunk/ (new configs)
  - config/continue/ (new configs)
  - config/langfuse/ (new export scripts)
---

# Single Source of Truth Sync for Skills, MCPs, and Config Across All Layers

## Context

The devflow ecosystem has 6 layers + 2 AI providers, each with its own config for skills, MCPs, hooks, and rules. Today these are configured independently with significant drift and gaps:

- **Agent Deck** (`~/.agent-deck/config.toml`): Template defines `[mcps.hindsight]` but live config has empty `[mcps]`. Skill pool dir doesn't exist. MCP pool disabled.
- **Claude Code**: 4 skill sources, 3 MCP sources, hooks in settings.json, 4 plugins, 5 agents — partially synced (only CLAUDE.md).
- **OpenCode**: Skills via git clone, plugin manually placed, `opencode.json` barely configured, no MCPs.
- **Continue.dev**: Has `~/.continue/skills/` (2 skills via npx), accepts `--mcp`/`--rule` per invocation — no devflow integration.
- **Worktrunk**: `~/.config/worktrunk/config.toml` doesn't exist despite rich hook system (10 types).
- **Langfuse**: Prompt templates, eval configs, dashboards all in Postgres DB — not version-controlled.
- **Cross-agent**: `~/.agents/skills/` managed by `npx skills` — separate from all other systems.

**Agent-deck's TUI Skill Manager (`s` key) and MCP Manager (`m` key) are currently useless** because nothing is registered in its pool.

## Problem Statement

There is no single source of truth. Skills, MCPs, and config are scattered across 8+ locations with no sync mechanism. Adding a new MCP or skill requires manually configuring it in 4+ places.

## Desired Outcome

A `devflow sync` command that propagates config from agent-deck (source of truth) to all consumers, plus a `devflow sync --status` that shows drift.

### Architecture

```
agent-deck config.toml     ← SOURCE OF TRUTH for MCPs, tools, pools
agent-deck skills/pool/    ← SOURCE OF TRUTH for skills
         │
         ▼ devflow sync
    ┌────┴──────────────────────────────────────────────┐
    │              │              │              │        │
    ▼              ▼              ▼              ▼        ▼
Claude Code    OpenCode     Continue.dev   Worktrunk   Langfuse
├ ~/.claude.json  ├ opencode.json  ├ wrapped by    ├ config.toml  ├ (export
│  (MCPs)         │  (MCPs)        │  devflow check │  (hooks)      │  prompts
├ ~/.claude/      ├ ~/.config/     │  --mcp/--rule  └──────────     │  via API)
│  skills/        │  opencode/     └────────────                    └─────────
│  settings.json  │  skills/
│  plugins        │  plugins/
└─────────────    └───────────
```

## Implementation Guide

### Phase 1: Populate Agent-Deck as Source of Truth

**Step 1.1 — Create agent-deck skill pool and register sources:**

```bash
# Create pool directory
mkdir -p ~/.agent-deck/skills/pool

# Register devflow skills as a source
agent-deck skill source add devflow ~/dev/devflow/devflow-plugin/skills 2>/dev/null || true

# Register superpowers as a source (Claude Code has these as a plugin, but agent-deck needs them)
agent-deck skill source add superpowers ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills 2>/dev/null || true

# Symlink devflow plugin skills into the pool
ln -sf ~/dev/devflow/devflow-plugin/skills/* ~/.agent-deck/skills/pool/ 2>/dev/null || true
ln -sf ~/dev/devflow/devflow-plugin/commands ~/.agent-deck/skills/pool/devflow-commands 2>/dev/null || true
```

**Step 1.2 — Populate agent-deck MCP config:**

Add to `~/.agent-deck/config.toml`:
```toml
[mcps.hindsight]
type = "http"
url = "http://localhost:8888/mcp/"

[mcp_pool]
enabled = true
auto_start = true
pool_all = true
exclude_mcps = []
fallback_to_stdio = true
show_pool_status = true
```

**Step 1.3 — Enable MCP pool:**

The pool shares MCP processes across sessions via Unix sockets. With `pool_all = true`, all MCPs defined in `[mcps.*]` are pooled. This reduces N sessions × M MCPs = N×M processes → M shared processes.

### Phase 2: Create `devflow sync` Command

**Step 2.1 — Create `lib/sync.sh`:**

```bash
devflow_sync() {
  section "Syncing devflow config across layers"

  # ── Read agent-deck as source of truth ──────────────────────
  local ad_config="${HOME}/.agent-deck/config.toml"
  [[ -f "$ad_config" ]] || die "Agent-deck config not found: $ad_config"

  # ── Sync MCPs ───────────────────────────────────────────────
  sync_mcps_to_claude_code
  sync_mcps_to_opencode

  # ── Sync Skills ─────────────────────────────────────────────
  sync_skills_to_claude_code
  sync_skills_to_opencode
  sync_skills_to_continue

  # ── Sync Worktrunk config ───────────────────────────────────
  sync_worktrunk_config

  # ── Report ──────────────────────────────────────────────────
  sync_status
}
```

**Step 2.2 — Implement sync functions:**

`sync_mcps_to_claude_code()`:
- Read `[mcps.*]` from agent-deck config.toml
- Parse each MCP entry (type, url/command, args)
- Use `claude mcp add -s user <name> <url>` for HTTP MCPs
- Use `claude mcp add -s user <name> <command> -- <args>` for stdio MCPs
- Skip MCPs already registered (check `claude mcp list`)

`sync_mcps_to_opencode()`:
- Read `[mcps.*]` from agent-deck config.toml
- Write to `~/.config/opencode/opencode.json` `mcpServers` section
- Use `jq` or `python3` for JSON manipulation
- Preserve existing opencode.json fields

`sync_skills_to_claude_code()`:
- Read agent-deck skill pool at `~/.agent-deck/skills/pool/`
- Symlink each skill directory to `~/.claude/skills/` (if not already there)
- Skip skills that are already delivered via plugins (superpowers)

`sync_skills_to_opencode()`:
- Read agent-deck skill pool
- Symlink to `~/.config/opencode/skills/` (if not already there)

`sync_skills_to_continue()`:
- Read agent-deck skill pool
- Symlink to `~/.continue/skills/` (if not already there)
- Note: continue.dev also has `~/.agents/skills/` managed by `npx skills` — don't overwrite those

`sync_worktrunk_config()`:
- If `~/.config/worktrunk/config.toml` doesn't exist, generate from devflow template
- Set defaults: worktree-path pattern, LLM commit command, merge behavior
- Register devflow hooks: post-create (copy-ignored), post-remove (cleanup)

**Step 2.3 — `sync_status` function:**

Show a matrix of what's synced and what's drifted:
```
Layer          Skills  MCPs    Hooks   Config
─────────────  ──────  ──────  ──────  ──────
Agent Deck     ✓ 11    ✓ 1     ✓       ✓
Claude Code    ✓ 4     ✓ 1     ✓       ✓
OpenCode       ✗ 0     ✗ 0     —       ✗
Continue.dev   ✓ 2     —       —       —
Worktrunk      —       —       ✗ 0     ✗
Langfuse       —       —       —       n/a
```

### Phase 3: Wire Into Devflow

**Step 3.1 — Add to `bin/devflow`:**
```bash
sync)    devflow_sync "$@" ;;
```

**Step 3.2 — Add `--sync` step to `devflow init`:**
After all layers are configured, run `devflow sync` as the final step.

**Step 3.3 — Add sync to `devflow up`:**
After services are healthy, run `devflow sync --quiet` to ensure everything is aligned.

**Step 3.4 — Wrap `devflow check` for continue.dev:**
Update `lib/check.sh` to pass MCP flags:
```bash
devflow_check() {
  local mcp_flags=""
  # Read MCPs from agent-deck config and build --mcp flags
  # ... parse [mcps.*] section ...
  cn check $mcp_flags "$@"
}
```

### Phase 4: Langfuse Config Export (Optional Enhancement)

If Langfuse has prompt templates or eval configs configured via the web UI:
- Add `devflow sync --export-langfuse` that calls Langfuse API to export:
  - Prompt templates → `config/langfuse/prompts/`
  - Evaluation configs → `config/langfuse/evaluations/`
- Add `devflow sync --import-langfuse` to restore from exported files
- This enables version-controlling Langfuse config in the devflow repo

## Acceptance Criteria

- [ ] `~/.agent-deck/skills/pool/` exists and contains devflow skills
- [ ] Agent-deck skill sources include `devflow` and `superpowers`
- [ ] Agent-deck `[mcps.hindsight]` is configured in live config.toml
- [ ] Agent-deck `[mcp_pool]` is enabled with `pool_all = true`
- [ ] `devflow sync` propagates MCPs to Claude Code (`~/.claude.json`)
- [ ] `devflow sync` propagates MCPs to OpenCode (`opencode.json`)
- [ ] `devflow sync` propagates skills to Claude Code (`~/.claude/skills/`)
- [ ] `devflow sync` propagates skills to OpenCode (`~/.config/opencode/skills/`)
- [ ] `devflow sync` propagates skills to Continue.dev (`~/.continue/skills/`)
- [ ] `devflow sync --status` shows sync state matrix
- [ ] `~/.config/worktrunk/config.toml` is generated with devflow defaults
- [ ] `devflow check` passes `--mcp` flags to `cn` for Hindsight access
- [ ] `devflow init` runs sync as final step
- [ ] `devflow up` runs quiet sync after services are healthy
- [ ] Agent-deck TUI Skill Manager (`s` key) shows devflow skills
- [ ] Agent-deck TUI MCP Manager (`m` key) shows Hindsight

## Technical Notes

- **Agent-deck cannot write to OpenCode or Claude Code configs natively.** The sync command bridges this gap.
- **Continue.dev has no persistent MCP config.** Wrapping `devflow check` with flags is the only reliable approach.
- **Worktrunk hooks use Jinja2 template variables** (`{{ branch }}`, `{{ repo }}`, etc.). Leverage these for automatic setup.
- **Cross-agent skills at `~/.agents/skills/`** are managed by `npx skills` CLI with `.skill-lock.json`. Don't overwrite — only add missing ones.
- **Langfuse export is optional** — many users won't have custom prompts/evals yet.
- **Idempotent:** `devflow sync` must be safe to run repeatedly. Use symlinks where possible (single source, multiple targets). Check before writing.
- **Drift detection:** Compare timestamps or checksums of synced files to detect when manual changes have diverged from agent-deck source.

## Verification

```bash
# After running devflow sync:

# 1. Check agent-deck skill pool
ls ~/.agent-deck/skills/pool/

# 2. Check agent-deck MCP config
grep -A2 '\[mcps.hindsight\]' ~/.agent-deck/config.toml

# 3. Check Claude Code MCPs
claude mcp list 2>&1 | grep hindsight

# 4. Check OpenCode MCPs
cat ~/.config/opencode/opencode.json | python3 -c "import json,sys; print(json.load(sys.stdin).get('mcpServers',{}).keys())"

# 5. Check skills in all targets
ls ~/.claude/skills/
ls ~/.config/opencode/skills/
ls ~/.continue/skills/

# 6. Check worktrunk config
cat ~/.config/worktrunk/config.toml

# 7. Full status
devflow sync --status
```
