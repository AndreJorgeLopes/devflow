#!/usr/bin/env bash
# devflow/lib/init.sh — devflow init implementation
# Initialize devflow for the current user, optionally scoped to a project.

devflow_init() {
  local project_dir="${1:-$(pwd)}"
  project_dir="$(cd "$project_dir" && pwd)"

  section "Initializing devflow"

  local root
  root="$(devflow_root)"
  local templates_dir="${root}/templates"
  local is_macos=false
  [[ "$(uname -s)" == "Darwin" ]] && is_macos=true

  # ── 1. Check prerequisites ─────────────────────────────────────────────────
  section "Checking prerequisites"

  local missing=0
  for cmd in docker git tmux; do
    if has_cmd "$cmd"; then
      ok "$cmd"
    else
      fail "$cmd — not found"
      missing=1
    fi
  done

  if $is_macos; then
    if has_cmd brew; then
      ok "brew"
    else
      fail "brew — not found (required on macOS)"
      missing=1
    fi
  fi

  [[ $missing -eq 1 ]] && die "Install missing prerequisites before continuing."

  # ── 2. Check/install tools ─────────────────────────────────────────────────
  section "Checking devflow tools"

  _install_via_brew() {
    local name="$1"
    local formula="${2:-$1}"
    if $is_macos && has_cmd brew; then
      info "Installing ${name} via brew..."
      brew install "${formula}" 2>/dev/null && ok "${name} installed" || warn "Could not install ${name} via brew — install manually"
    else
      warn "${name} not found — install manually"
    fi
  }

  # Agent Deck
  if has_cmd agent-deck; then
    ok "agent-deck"
  else
    if $is_macos && has_cmd brew; then
      info "Installing agent-deck via brew..."
      brew install asheshgoplani/tap/agent-deck 2>/dev/null && ok "agent-deck installed" || warn "Could not install agent-deck via brew — install manually"
    else
      info "Installing agent-deck via install script..."
      curl -fsSL https://raw.githubusercontent.com/asheshgoplani/agent-deck/main/install.sh | bash 2>/dev/null \
        && ok "agent-deck installed" \
        || warn "Could not install agent-deck — install manually"
    fi
  fi

  # Worktrunk
  if has_cmd wt; then
    ok "worktrunk (wt)"
  else
    _install_via_brew "worktrunk"
  fi

  # Continue.dev CLI — distributed via npm, not Homebrew
  if has_cmd cn; then
    ok "continue.dev CLI (cn)"
  else
    if has_cmd npm; then
      info "Installing continue.dev CLI via npm..."
      npm install -g @continuedev/cli 2>/dev/null && ok "continue.dev CLI (cn) installed" || warn "Could not install cn — run: npm i -g @continuedev/cli"
    elif has_cmd yarn; then
      info "Installing continue.dev CLI via yarn..."
      yarn global add @continuedev/cli 2>/dev/null && ok "continue.dev CLI (cn) installed" || warn "Could not install cn — run: npm i -g @continuedev/cli"
    else
      warn "continue.dev CLI (cn) not found — install with: npm i -g @continuedev/cli"
    fi
  fi

  # uv (Python) — needed for Hindsight
  if has_cmd uv || has_cmd uvx; then
    ok "uv"
  else
    if $is_macos && has_cmd brew; then
      info "Installing uv via brew..."
      brew install uv 2>/dev/null && ok "uv installed" || warn "Could not install uv via brew — install manually (https://docs.astral.sh/uv/)"
    else
      warn "uv not found — install manually (https://docs.astral.sh/uv/)"
    fi
  fi

  # Hindsight — install profile via uvx
  if has_cmd uvx; then
    info "Setting up Hindsight profile..."
    uvx hindsight-embed profile create main \
      --port 8888 \
      --env HINDSIGHT_API_LLM_PROVIDER=anthropic \
      --env HINDSIGHT_API_LLM_API_KEY=placeholder 2>/dev/null \
      && ok "Hindsight profile 'main' created" \
      || skip "Hindsight profile 'main' already exists or could not be created"
    uvx hindsight-embed profile set-active main 2>/dev/null
    info "Set your API key: uvx hindsight-embed profile set-env main HINDSIGHT_API_LLM_API_KEY <your-key>"
  else
    skip "uvx not available — skipping Hindsight profile setup"
  fi

  # ── 3. User-scoped config (CLAUDE.md, AGENTS.md) ──────────────────────────
  # These go in ~/.claude/ so they apply across ALL projects for this user.
  # They do NOT pollute the team's project-level CLAUDE.md.
  section "Setting up user-scoped agent config"

  local claude_home="${HOME}/.claude"
  mkdir -p "${claude_home}"

  # User-scoped CLAUDE.md
  if [[ -f "${claude_home}/CLAUDE.md" ]]; then
    if ! grep -q "<!-- devflow -->" "${claude_home}/CLAUDE.md" 2>/dev/null; then
      info "~/.claude/CLAUDE.md exists — appending devflow section"
      printf "\n" >> "${claude_home}/CLAUDE.md"
      cat "${templates_dir}/CLAUDE.md.tmpl" >> "${claude_home}/CLAUDE.md"
      ok "Appended devflow section to ~/.claude/CLAUDE.md"
    else
      skip "~/.claude/CLAUDE.md already contains devflow section"
    fi
  else
    cp "${templates_dir}/CLAUDE.md.tmpl" "${claude_home}/CLAUDE.md"
    ok "Created ~/.claude/CLAUDE.md"
  fi

  # User-scoped AGENTS.md
  if [[ -f "${claude_home}/AGENTS.md" ]]; then
    skip "~/.claude/AGENTS.md already exists"
  else
    cp "${templates_dir}/AGENTS.md.tmpl" "${claude_home}/AGENTS.md"
    ok "Created ~/.claude/AGENTS.md"
  fi

  # ── 4. Project-scoped config (worktree, code review checks) ───────────────
  # These ARE per-project because they configure project-specific tooling.
  section "Setting up project files in ${project_dir}"

  # .worktrunk.toml — worktree config is inherently per-repo
  if [[ -f "${project_dir}/.worktrunk.toml" ]]; then
    skip ".worktrunk.toml already exists"
  else
    cp "${templates_dir}/.worktrunk.toml.tmpl" "${project_dir}/.worktrunk.toml"
    ok "Created .worktrunk.toml"
  fi

  # .continue/checks/ — review rules are per-project (team can customize)
  if [[ -d "${templates_dir}/.continue/checks" ]]; then
    mkdir -p "${project_dir}/.continue/checks"
    local copied=0
    for check_file in "${templates_dir}/.continue/checks/"*.md; do
      local basename
      basename="$(basename "$check_file")"
      if [[ ! -f "${project_dir}/.continue/checks/${basename}" ]]; then
        cp "$check_file" "${project_dir}/.continue/checks/${basename}"
        ((copied++))
      fi
    done
    if [[ $copied -gt 0 ]]; then
      ok "Copied ${copied} check file(s) to .continue/checks/"
    else
      skip ".continue/checks/ already up to date"
    fi
  fi

  # ── 5. Install Claude Code plugins ────────────────────────────────────────
  if has_cmd claude; then
    section "Installing Claude Code plugins"
    claude plugin marketplace add asheshgoplani/agent-deck 2>/dev/null
    claude plugin install agent-deck@agent-deck 2>/dev/null \
      && ok "agent-deck plugin installed" \
      || skip "agent-deck plugin already installed or not available"
    claude plugin marketplace add max-sixty/worktrunk 2>/dev/null
    claude plugin install worktrunk@worktrunk 2>/dev/null \
      && ok "worktrunk plugin installed" \
      || skip "worktrunk plugin already installed or not available"
  else
    skip "Claude Code not installed — skipping plugin install"
  fi

  # ── 6. Install skills ─────────────────────────────────────────────────────
  section "Installing skills"

  # Hindsight skill for Claude Code
  if has_cmd claude; then
    local claude_skills_dir="${HOME}/.claude/skills/hindsight"
    mkdir -p "${claude_skills_dir}"
    if [[ -f "${root}/skills/memory-recall/recall-before-task.md" ]]; then
      cp "${root}/skills/memory-recall/recall-before-task.md" "${claude_skills_dir}/SKILL.md"
      ok "Hindsight skill installed for Claude Code (~/.claude/skills/hindsight/SKILL.md)"
    else
      warn "Hindsight skill template not found in devflow skills"
    fi
  fi

  # Skills for OpenCode
  if has_cmd opencode; then
    # Agent Deck skill — download from GitHub
    local oc_ad_skill_dir="${HOME}/.claude/skills/agent-deck"
    mkdir -p "${oc_ad_skill_dir}"
    info "Downloading Agent Deck skill for OpenCode..."
    curl -fsSL "https://raw.githubusercontent.com/asheshgoplani/agent-deck/main/skills/SKILL.md" \
      -o "${oc_ad_skill_dir}/SKILL.md" 2>/dev/null \
      && ok "Agent Deck skill installed (~/.claude/skills/agent-deck/SKILL.md)" \
      || warn "Could not download Agent Deck skill — install manually"

    # Hindsight skill for OpenCode
    local oc_hs_skill_dir="${HOME}/.opencode/skills/hindsight"
    mkdir -p "${oc_hs_skill_dir}"
    if [[ -f "${root}/skills/memory-recall/recall-before-task.md" ]]; then
      cp "${root}/skills/memory-recall/recall-before-task.md" "${oc_hs_skill_dir}/SKILL.md"
      ok "Hindsight skill installed for OpenCode (~/.opencode/skills/hindsight/SKILL.md)"
    else
      warn "Hindsight skill template not found in devflow skills"
    fi
  fi

  # ── 7. Configure Hindsight MCP (user-scoped) ──────────────────────────────
  section "Configuring Hindsight MCP"

  local hindsight_url="${HINDSIGHT_API:-http://localhost:8888}"

  # Claude Code — MCP config is already user-scoped by default
  if has_cmd claude; then
    info "Adding Hindsight MCP to Claude Code..."
    claude mcp add \
      --transport http \
      -s user \
      hindsight \
      "${hindsight_url}/mcp/" 2>/dev/null \
      && ok "Hindsight MCP added to Claude Code" \
      || warn "Could not add MCP to Claude Code — add manually"
  else
    skip "Claude Code not installed — skipping MCP config"
  fi

  # OpenCode — user-scoped config at ~/.config/opencode/
  if has_cmd opencode; then
    info "Configuring Hindsight MCP for OpenCode..."
    local oc_config_dir="${HOME}/.config/opencode"
    mkdir -p "$oc_config_dir"

    local oc_config_file="${oc_config_dir}/opencode.json"
    if [[ -f "$oc_config_file" ]]; then
      if has_cmd jq; then
        # Fix trailing commas (common in hand-edited JSON) before merging
        local tmp sanitized
        tmp=$(mktemp)
        sanitized=$(mktemp)
        sed 's/,\([[:space:]]*[}]]\)/\1/g' "$oc_config_file" > "$sanitized"
        if jq '.mcpServers.hindsight = {"type": "sse", "url": "'"${hindsight_url}/mcp/sse"'"}' \
          "$sanitized" > "$tmp" 2>/dev/null; then
          mv "$tmp" "$oc_config_file"
          ok "Hindsight MCP added to OpenCode config"
        else
          warn "Could not merge OpenCode config — add Hindsight MCP manually"
        fi
        rm -f "$tmp" "$sanitized"
      else
        warn "jq not found — cannot merge OpenCode config. Add Hindsight MCP manually."
      fi
    else
      cat > "$oc_config_file" <<-OJSON
{
  "\$schema": "https://opencode.ai/config.json",
  "mcpServers": {
    "hindsight": {
      "type": "sse",
      "url": "${hindsight_url}/mcp/sse"
    }
  }
}
OJSON
      ok "Created OpenCode config with Hindsight MCP"
    fi
  else
    skip "OpenCode not installed — skipping MCP config"
  fi

  # ── 8. Worktrunk shell integration ────────────────────────────────────────
  if has_cmd wt; then
    section "Configuring Worktrunk shell integration"
    echo "y" | wt config shell install 2>/dev/null \
      && ok "Worktrunk shell integration installed" \
      || skip "Worktrunk shell integration already configured or not available"
  fi

  # ── 9. Summary ──────────────────────────────────────────────────────────────
  section "Init complete"
  log ""
  log "User-scoped (applies to all projects):"
  detail "~/.claude/CLAUDE.md    — Agent instructions with memory workflow"
  detail "~/.claude/AGENTS.md    — Multi-agent coordination"
  detail "MCP: Hindsight         — Persistent memory server"
  detail "Claude Code plugins    — agent-deck, worktrunk"
  detail "Skills                 — Hindsight (Claude Code + OpenCode)"
  log ""
  log "Project-scoped (${project_dir}):"
  detail ".worktrunk.toml        — Git worktree config"
  detail ".continue/checks/      — Code review check files"
  log ""
  log "Next steps:"
  detail "devflow up          — Start Docker services (Hindsight + Langfuse)"
  detail "devflow seed        — Seed Hindsight memory from project files"
  detail "devflow status      — Check status of all layers"
  detail "devflow skills list — Browse available skills"
}
