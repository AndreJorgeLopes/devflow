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
  printf "\n${BOLD}Layer 1: Hindsight${RESET} (memory MCP, Docker)\n"
  if timeout 5 docker info >/dev/null 2>&1; then
    if docker_compose -f "$compose_file" ps --status running 2>/dev/null | grep -q "hindsight"; then
      ok "Hindsight container running"
    else
      fail "Hindsight container not running"
    fi
  else
    fail "Docker not running"
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
  local proj
  proj="$(project_root 2>/dev/null || echo "")"
  if [[ -n "$proj" && -f "${proj}/CLAUDE.md" ]]; then
    ok "CLAUDE.md found in project"
  elif [[ -n "$proj" ]]; then
    fail "CLAUDE.md not found in project root"
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

  # ── Layer 6: Langfuse ──────────────────────────────────────────────────────
  printf "\n${BOLD}Layer 6: Langfuse${RESET} (observability, Docker)\n"
  if timeout 5 docker info >/dev/null 2>&1; then
    if docker_compose -f "$compose_file" ps --status running 2>/dev/null | grep -q "langfuse"; then
      ok "Langfuse container running"
    else
      fail "Langfuse container not running"
    fi
  else
    fail "Docker not running"
  fi

  echo ""
}
