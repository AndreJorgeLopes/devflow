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
  local docker_daemon_ok=true
  for cmd in docker git tmux; do
    if has_cmd "$cmd"; then
      ok "$cmd"
      # Enhanced Docker check: CLI exists, but is the daemon running?
      if [[ "$cmd" == "docker" ]]; then
        if ! timeout 5 docker info >/dev/null 2>&1; then
          docker_daemon_ok=false
          warn "Docker CLI found but daemon not running"
          local runtimes=()
          has_cmd colima && runtimes+=("colima start")
          [[ -d "/Applications/Docker.app" ]] && runtimes+=("open -a Docker")
          has_cmd orbctl && runtimes+=("orbctl start")
          if [[ ${#runtimes[@]} -gt 0 ]]; then
            local suggestions
            suggestions=$(printf "'%s'" "${runtimes[0]}")
            for ((i=1; i<${#runtimes[@]}; i++)); do
              suggestions+=", or '${runtimes[$i]}'"
            done
            info "  Start with: ${suggestions}"
          else
            info "  Install a runtime: colima (brew install colima) or Docker Desktop"
          fi
          warn "Layers requiring Docker (Hindsight, Langfuse) won't work until daemon is running"
        fi
      fi
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

  # Code Review CLI — uses claude (primary) or opencode (fallback), no install needed
  if has_cmd claude; then
    ok "Code review CLI: claude"
  elif has_cmd opencode; then
    ok "Code review CLI: opencode (fallback)"
  else
    warn "No code review CLI found — install Claude Code or OpenCode"
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

  # Hindsight — install profile via uvx with interactive provider selection
  if has_cmd uvx; then
    if [[ -f "${HOME}/.hindsight/profiles/main.env" ]]; then
      local current_provider
      current_provider="$(grep HINDSIGHT_API_LLM_PROVIDER "${HOME}/.hindsight/profiles/main.env" 2>/dev/null | cut -d= -f2)"
      ok "Hindsight profile 'main' exists (provider: ${current_provider:-unknown})"
    else
      section "Configuring Hindsight memory"
      log "Choose an LLM provider for Hindsight memory processing."
      log ""
      printf "  ${BOLD}1)${RESET} Claude Code      ${DIM}— uses your Claude Code subscription, no API key needed${RESET}\n"
      printf "  ${BOLD}2)${RESET} OpenAI Codex     ${DIM}— uses your OpenAI Codex subscription, no API key needed${RESET}\n"
      printf "  ${BOLD}3)${RESET} Anthropic API    ${DIM}— requires ANTHROPIC_API_KEY${RESET}\n"
      printf "  ${BOLD}4)${RESET} OpenAI API       ${DIM}— requires OPENAI_API_KEY${RESET}\n"
      printf "  ${BOLD}5)${RESET} Groq             ${DIM}— requires GROQ_API_KEY${RESET}\n"
      printf "  ${BOLD}6)${RESET} Ollama           ${DIM}— free, runs locally, no API key${RESET}\n"
      log ""
      printf "  Select provider [1]: "
      local provider_choice
      read -r provider_choice </dev/tty 2>/dev/null || provider_choice="1"
      provider_choice="${provider_choice:-1}"

      local hs_provider="" hs_needs_key=false
      case "$provider_choice" in
        1) hs_provider="claude-code" ;;
        2) hs_provider="openai-codex" ;;
        3) hs_provider="anthropic"; hs_needs_key=true ;;
        4) hs_provider="openai"; hs_needs_key=true ;;
        5) hs_provider="groq"; hs_needs_key=true ;;
        6) hs_provider="ollama" ;;
        *) hs_provider="claude-code"; warn "Invalid choice, defaulting to Claude Code" ;;
      esac

      local create_args=(main --port 8888 --env "HINDSIGHT_API_LLM_PROVIDER=${hs_provider}")

      if $hs_needs_key; then
        printf "  Enter API key: "
        local api_key
        read -rs api_key </dev/tty 2>/dev/null || api_key=""
        echo ""
        if [[ -n "$api_key" ]]; then
          create_args+=(--env "HINDSIGHT_API_LLM_API_KEY=${api_key}")
        else
          create_args+=(--env "HINDSIGHT_API_LLM_API_KEY=placeholder")
          warn "No API key provided. Set it later: uvx hindsight-embed profile set-env main HINDSIGHT_API_LLM_API_KEY <key>"
        fi
      fi

      uvx hindsight-embed profile create "${create_args[@]}" 2>/dev/null \
        && ok "Hindsight profile 'main' created (provider: ${hs_provider})" \
        || warn "Hindsight profile creation failed — configure manually: uvx hindsight-embed configure"
      uvx hindsight-embed profile set-active main 2>/dev/null
    fi
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

  # ── 3b. Claude Code trust configuration ────────────────────────────────────
  section "Claude Code Trust Configuration"
  info "devflow creates worktrees in dynamic paths. To avoid trust dialogs"
  info "interrupting automated workflows, we can trust your home directory."
  info "This only skips the initial project trust prompt — file and tool"
  info "permissions are still enforced per-session."
  echo ""
  printf "${YELLOW}Trust ${HOME} for Claude Code? [Y/n] ${RESET}"
  read -r answer </dev/tty 2>/dev/null || answer="Y"
  if [[ "$answer" != "n" && "$answer" != "N" ]]; then
    if [[ -f "${HOME}/.claude.json" ]]; then
      python3 -c "
import json, os
config_path = os.path.expanduser('~/.claude.json')
with open(config_path, 'r+') as f:
    d = json.load(f)
    home = os.path.expanduser('~')
    projects = d.setdefault('projects', {})
    home_project = projects.setdefault(home, {})
    home_project['hasTrustDialogAccepted'] = True
    f.seek(0)
    json.dump(d, f, indent=2)
    f.truncate()
"
      ok "Home directory trusted for Claude Code"
    else
      warn "~/.claude.json not found — run Claude Code once first, then re-run devflow init"
    fi
  else
    skip "Skipped — you'll see trust dialogs for new worktrees"
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

  # .devflow/checks/ — review rules are per-project (team can customize)
  if [[ -d "${templates_dir}/.devflow/checks" ]]; then
    mkdir -p "${project_dir}/.devflow/checks"
    local copied=0
    for check_file in "${templates_dir}/.devflow/checks/"*.md; do
      local basename
      basename="$(basename "$check_file")"
      if [[ ! -f "${project_dir}/.devflow/checks/${basename}" ]]; then
        cp "$check_file" "${project_dir}/.devflow/checks/${basename}"
        ((copied++))
      fi
    done
    if [[ $copied -gt 0 ]]; then
      ok "Copied ${copied} check file(s) to .devflow/checks/"
    else
      skip ".devflow/checks/ already up to date"
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

  # ── 5b. Agent Deck Conductor Setup ──────────────────────────────────────
  section "Agent Deck Conductor Setup"
  if has_cmd agent-deck; then
    info "Setting up a development conductor for automated session monitoring..."

    # Create conductor if it doesn't exist
    if ! agent-deck conductor list 2>/dev/null | grep -q "dev"; then
      agent-deck conductor setup dev --description "Devflow development monitor" 2>/dev/null || true
      ok "Development conductor created"
    else
      skip "Development conductor already exists"
    fi
  else
    skip "agent-deck not installed — skipping conductor setup"
  fi

  # ── 5c. Agent Deck Session Groups ─────────────────────────────────────────
  section "Agent Deck Session Groups"
  if has_cmd agent-deck; then
    local project_name
    project_name="$(basename "$(git -C "${project_dir}" remote get-url origin 2>/dev/null | sed 's/.*\///' | sed 's/\.git$//')" 2>/dev/null || basename "${project_dir}")"

    for group in "${project_name}" "${project_name}/features" "${project_name}/bugfixes" "${project_name}/reviews"; do
      if ! agent-deck group list 2>/dev/null | grep -q "$group"; then
        agent-deck group create "$group" 2>/dev/null || true
      fi
    done
    ok "Session groups created: ${project_name}/{features,bugfixes,reviews}"
  else
    skip "agent-deck not installed — skipping group setup"
  fi

  # ── 6. Install devflow commands & skills ──────────────────────────────────
  if has_cmd claude; then
    section "Installing devflow commands & skills"

    local commands_link="${HOME}/.claude/commands/devflow"
    local skills_link="${HOME}/.claude/skills/devflow-recall"
    local commands_target="${root}/devflow-plugin/commands"
    local skills_target="${root}/devflow-plugin/skills/recall-before-task"

    mkdir -p "${HOME}/.claude/commands" "${HOME}/.claude/skills"

    # Commands symlink
    if [[ -L "${commands_link}" ]]; then
      local current_target
      current_target="$(readlink "${commands_link}")"
      if [[ "${current_target}" == "${commands_target}" ]]; then
        ok "Devflow commands symlink healthy (${commands_link})"
      else
        warn "Commands symlink points to ${current_target}, expected ${commands_target}"
        ln -sfn "${commands_target}" "${commands_link}"
        ok "Commands symlink updated"
      fi
    elif [[ -d "${commands_link}" ]]; then
      warn "${commands_link} is a directory, not a symlink — skipping (manual cleanup needed)"
    else
      ln -sfn "${commands_target}" "${commands_link}"
      ok "Devflow commands installed (~/.claude/commands/devflow)"
    fi

    # Skills symlink
    if [[ -L "${skills_link}" ]]; then
      local current_skills_target
      current_skills_target="$(readlink "${skills_link}")"
      if [[ "${current_skills_target}" == "${skills_target}" ]]; then
        ok "Devflow skills symlink healthy (${skills_link})"
      else
        ln -sfn "${skills_target}" "${skills_link}"
        ok "Devflow skills symlink updated"
      fi
    elif [[ ! -e "${skills_link}" ]]; then
      ln -sfn "${skills_target}" "${skills_link}"
      ok "Devflow recall skill installed (~/.claude/skills/devflow-recall)"
    else
      skip "Devflow skill path exists but is not a symlink — skipping"
    fi
  else
    skip "Claude Code not installed — skipping devflow commands"
  fi

  # ── 6b. Install third-party skills ──────────────────────────────────────
  section "Installing third-party skills"

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
  detail "Devflow commands       — /devflow:new-feature, /devflow:create-pr, etc."
  detail "Skills                 — Hindsight, devflow-recall (Claude Code + OpenCode)"
  log ""
  log "Project-scoped (${project_dir}):"
  detail ".worktrunk.toml        — Git worktree config"
  detail ".devflow/checks/       — Code review check files"
  log ""
  log "Next steps:"
  detail "uvx hindsight-embed daemon start   — Start Hindsight memory daemon"
  detail "devflow up                         — Start Langfuse (Docker)"
  detail "devflow seed                       — Seed memory from project files"
  detail "devflow status                     — Check status of all layers"
  detail "devflow skills list                — Browse available skills"
  log ""
  log "Integrations:"
  info "  Web dashboard:   agent-deck web (or devflow web)"
  info "  Chrome extension: Install from Chrome Web Store, enable with /chrome in Claude Code"
}
