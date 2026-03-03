#!/usr/bin/env bash
# devflow/lib/init.sh — devflow init implementation
# Initialize a project with all 6 layers of the devflow stack.

devflow_init() {
  local project_dir="${1:-$(pwd)}"
  project_dir="$(cd "$project_dir" && pwd)"

  section "Initializing devflow in $project_dir"

  local root
  root="$(devflow_root)"

  # ── 1. Check prerequisites ─────────────────────────────────────────────────
  section "Checking prerequisites"

  local missing=0
  for cmd in docker git tmux brew; do
    if has_cmd "$cmd"; then
      ok "$cmd"
    else
      fail "$cmd — not found"
      missing=1
    fi
  done
  [[ $missing -eq 1 ]] && die "Install missing prerequisites before continuing."

  # ── 2. Check/install tools ─────────────────────────────────────────────────
  section "Checking devflow tools"

  # Agent Deck
  if has_cmd agent-deck; then
    ok "agent-deck"
  else
    info "Installing agent-deck via brew..."
    brew install agent-deck 2>/dev/null && ok "agent-deck installed" || warn "Could not install agent-deck — install manually"
  fi

  # Worktrunk
  if has_cmd wt; then
    ok "worktrunk (wt)"
  else
    info "Installing worktrunk via brew..."
    brew install worktrunk 2>/dev/null && ok "worktrunk installed" || warn "Could not install worktrunk — install manually"
  fi

  # Continue.dev CLI
  if has_cmd cn; then
    ok "continue.dev CLI (cn)"
  else
    info "Installing continue.dev CLI via npm..."
    npm install -g @anthropic/continue 2>/dev/null && ok "continue.dev CLI installed" || warn "Could not install cn — install manually: npm install -g @anthropic/continue"
  fi

  # ── 3. Copy template files ─────────────────────────────────────────────────
  section "Setting up project files"

  local templates_dir="${root}/templates"

  # CLAUDE.md — append if exists, create if not
  if [[ -f "${project_dir}/CLAUDE.md" ]]; then
    info "CLAUDE.md already exists — appending devflow section"
    if ! grep -q "<!-- devflow -->" "${project_dir}/CLAUDE.md" 2>/dev/null; then
      printf "\n" >> "${project_dir}/CLAUDE.md"
      cat "${templates_dir}/CLAUDE.md.tmpl" >> "${project_dir}/CLAUDE.md"
      ok "Appended devflow section to CLAUDE.md"
    else
      skip "CLAUDE.md already contains devflow section"
    fi
  else
    cp "${templates_dir}/CLAUDE.md.tmpl" "${project_dir}/CLAUDE.md"
    ok "Created CLAUDE.md"
  fi

  # AGENTS.md
  if [[ -f "${project_dir}/AGENTS.md" ]]; then
    skip "AGENTS.md already exists"
  else
    cp "${templates_dir}/AGENTS.md.tmpl" "${project_dir}/AGENTS.md"
    ok "Created AGENTS.md"
  fi

  # .worktrunk.toml
  if [[ -f "${project_dir}/.worktrunk.toml" ]]; then
    skip ".worktrunk.toml already exists"
  else
    cp "${templates_dir}/.worktrunk.toml.tmpl" "${project_dir}/.worktrunk.toml"
    ok "Created .worktrunk.toml"
  fi

  # .continue/checks/
  if [[ -d "${templates_dir}/.continue/checks" ]]; then
    mkdir -p "${project_dir}/.continue/checks"
    cp -r "${templates_dir}/.continue/checks/"* "${project_dir}/.continue/checks/" 2>/dev/null
    ok "Copied .continue/checks/"
  else
    skip "No .continue/checks template found"
  fi

  # ── 4. Configure Hindsight MCP ─────────────────────────────────────────────
  section "Configuring Hindsight MCP"

  local hindsight_url="${HINDSIGHT_API:-http://localhost:8888}"

  # Claude Code
  if has_cmd claude; then
    info "Adding Hindsight MCP to Claude Code..."
    claude mcp add hindsight \
      --transport sse \
      "${hindsight_url}/mcp/sse" 2>/dev/null \
      && ok "Hindsight MCP added to Claude Code" \
      || warn "Could not add MCP to Claude Code — add manually"
  else
    skip "Claude Code not installed — skipping MCP config"
  fi

  # OpenCode
  if has_cmd opencode; then
    info "Configuring Hindsight MCP for OpenCode..."
    local oc_config_dir="${project_dir}/.opencode"
    mkdir -p "$oc_config_dir"

    local oc_config_file="${oc_config_dir}/config.json"
    if [[ -f "$oc_config_file" ]]; then
      # Merge MCP config into existing file (simple append to mcpServers)
      local tmp
      tmp=$(mktemp)
      if has_cmd jq; then
        jq '.mcpServers.hindsight = {"type": "sse", "url": "'"${hindsight_url}/mcp/sse"'"}' \
          "$oc_config_file" > "$tmp" && mv "$tmp" "$oc_config_file"
        ok "Hindsight MCP added to OpenCode config"
      else
        warn "jq not found — cannot merge OpenCode config. Add Hindsight MCP manually."
        rm -f "$tmp"
      fi
    else
      cat > "$oc_config_file" <<-OJSON
{
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

  # ── 5. Summary ──────────────────────────────────────────────────────────────
  section "Init complete"
  log "Project initialized at: ${project_dir}"
  log ""
  log "Next steps:"
  detail "devflow up          — Start Docker services (Hindsight + Langfuse)"
  detail "devflow seed        — Seed Hindsight memory from project files"
  detail "devflow status      — Check status of all layers"
  detail "devflow skills list — Browse available skills"
}
