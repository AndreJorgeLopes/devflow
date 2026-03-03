#!/usr/bin/env bash
# devflow/lib/services.sh — devflow up/down/status implementation
# Manages Docker services (Hindsight + Langfuse) and reports layer status.

devflow_up() {
  local compose_file
  compose_file="$(devflow_compose_file)"

  [[ -f "$compose_file" ]] || die "Docker compose file not found: $compose_file"
  ensure_docker

  section "Starting devflow services"
  docker_compose -f "$compose_file" up -d

  log "Services started. Run 'devflow status' to verify."
}

devflow_down() {
  local compose_file
  compose_file="$(devflow_compose_file)"

  [[ -f "$compose_file" ]] || die "Docker compose file not found: $compose_file"
  ensure_docker

  section "Stopping devflow services"
  docker_compose -f "$compose_file" down

  log "Services stopped."
}

devflow_status() {
  section "devflow status"

  local compose_file
  compose_file="$(devflow_compose_file)"

  # ── Layer 1: Hindsight (Memory MCP) ────────────────────────────────────────
  printf "\n${BOLD}Layer 1: Hindsight${RESET} (memory MCP)\n"

  local hindsight_runtime_found=false

  # Check local daemon first (uvx hindsight-embed)
  if has_cmd uvx; then
    if uvx hindsight-embed daemon status 2>/dev/null | grep -qi "running"; then
      ok "Hindsight local daemon running"
      hindsight_runtime_found=true
    fi
  fi

  # Fall back to Docker container check
  if ! $hindsight_runtime_found; then
    if timeout 5 docker info >/dev/null 2>&1; then
      if docker_compose -f "$compose_file" ps --status running 2>/dev/null | grep -q "hindsight"; then
        ok "Hindsight container running (Docker)"
        hindsight_runtime_found=true
      else
        fail "Hindsight container not running"
      fi
    else
      fail "Docker runtime not running (try: colima start)"
    fi
  fi

  if hindsight_available; then
    ok "Hindsight API reachable at ${HINDSIGHT_API}"
  else
    fail "Hindsight API not reachable at ${HINDSIGHT_API}"
  fi

  # ── Layer 2: Agent Deck ────────────────────────────────────────────────────
  printf "\n${BOLD}Layer 2: Agent Deck${RESET} (session wrapper)\n"
  if has_cmd agent-deck; then
    ok "agent-deck installed"
  else
    fail "agent-deck not installed"
  fi

  # ── Layer 3: Worktrunk ─────────────────────────────────────────────────────
  printf "\n${BOLD}Layer 3: Worktrunk${RESET} (git worktrees)\n"
  if has_cmd wt; then
    ok "worktrunk (wt) installed"
  else
    fail "worktrunk (wt) not installed"
  fi

  # ── Layer 4: Continue.dev ──────────────────────────────────────────────────
  printf "\n${BOLD}Layer 4: Continue.dev${RESET} (code review)\n"
  if has_cmd cn; then
    ok "continue.dev CLI (cn) installed"
  else
    fail "continue.dev CLI (cn) not installed"
  fi

  # ── Layer 5: CLAUDE.md + Skills ────────────────────────────────────────────
  printf "\n${BOLD}Layer 5: CLAUDE.md + Skills${RESET} (process discipline)\n"

  # Check user-scoped CLAUDE.md
  if [[ -f "${HOME}/.claude/CLAUDE.md" ]]; then
    ok "~/.claude/CLAUDE.md found (user-scoped)"
  else
    fail "~/.claude/CLAUDE.md not found"
  fi

  # Check project-scoped CLAUDE.md
  local proj
  proj="$(project_root 2>/dev/null || echo "")"
  if [[ -n "$proj" && -f "${proj}/CLAUDE.md" ]]; then
    ok "CLAUDE.md found in project"
  elif [[ -n "$proj" ]]; then
    skip "No project-scoped CLAUDE.md (optional — user-scoped config is active)"
  else
    skip "Not in a git repository"
  fi

  local root
  root="$(devflow_root)"
  local skill_count=0
  if [[ -f "${root}/skills/registry.json" ]]; then
    skill_count=$(jq '.skills | length' "${root}/skills/registry.json" 2>/dev/null || echo 0)
  fi
  info "${skill_count} skills available in registry"

  # Claude Code plugin status
  if has_cmd claude; then
    printf "\n${BOLD}Claude Code Plugins${RESET}\n"
    if claude plugin list 2>/dev/null | grep -q "agent-deck"; then
      ok "agent-deck plugin installed"
    else
      fail "agent-deck plugin not installed"
    fi
    if claude plugin list 2>/dev/null | grep -q "worktrunk"; then
      ok "worktrunk plugin installed"
    else
      fail "worktrunk plugin not installed"
    fi
  fi

  # ── Layer 6: Langfuse ──────────────────────────────────────────────────────
  printf "\n${BOLD}Layer 6: Langfuse${RESET} (observability, Docker)\n"
  if timeout 5 docker info >/dev/null 2>&1; then
    if docker_compose -f "$compose_file" ps --status running 2>/dev/null | grep -q "langfuse"; then
      ok "Langfuse container running"
    else
      fail "Langfuse container not running"
    fi
  else
    fail "Docker runtime not running (try: colima start)"
  fi

  echo ""
}
