#!/usr/bin/env bash
# devflow/lib/services.sh — devflow up/down/status implementation
# Manages Docker services (Hindsight + Langfuse) and reports layer status.

devflow_up() {
  local compose_file
  compose_file="$(devflow_compose_file)"

  [[ -f "$compose_file" ]] || die "Docker compose file not found: $compose_file"

  # 1. Validate Docker CLI + daemon
  section "Checking Docker"
  ensure_docker
  ok "Docker daemon running"

  # 2. Start Docker services
  section "Starting Docker services"
  docker_compose -f "$compose_file" up -d
  ok "Docker compose services started"

  # 3. Wait for health checks (Hindsight /health endpoint)
  section "Waiting for services to become healthy"
  local retries=0 max_retries=30
  while (( retries < max_retries )); do
    if hindsight_available; then
      ok "Hindsight API healthy"
      break
    fi
    retries=$((retries + 1))
    printf "  ${DIM}waiting for Hindsight... (%d/%d)${RESET}\r" "$retries" "$max_retries"
    sleep 2
  done
  if (( retries >= max_retries )); then
    warn "Hindsight API did not become healthy after $((max_retries * 2))s — check logs with: docker compose -f \"$compose_file\" logs hindsight"
  fi

  # 4. Validate CLI tools
  section "Checking CLI tools"
  if has_cmd agent-deck; then ok "agent-deck on PATH"; else warn "agent-deck not found on PATH"; fi
  if has_cmd wt;         then ok "wt on PATH";         else warn "wt (worktrunk) not found on PATH"; fi
  if has_cmd claude; then ok "claude on PATH (code review: primary)"
  elif has_cmd opencode; then ok "opencode on PATH (code review: fallback)"
  else warn "No code review CLI found (claude or opencode)"; fi

  # 5. Check CLAUDE.md
  if [[ -f "${HOME}/.claude/CLAUDE.md" ]]; then
    ok "~/.claude/CLAUDE.md exists"
  else
    warn "~/.claude/CLAUDE.md not found — run 'devflow init' to create it"
  fi

  # 6. Summary
  section "devflow is up"
  info "Hindsight API : ${HINDSIGHT_API:-http://localhost:8888}"
  info "Hindsight UI  : http://localhost:9999"
  info "Langfuse      : http://localhost:3100"
  echo ""
}

devflow_down() {
  local compose_file
  compose_file="$(devflow_compose_file)"

  [[ -f "$compose_file" ]] || die "Docker compose file not found: $compose_file"
  ensure_docker

  section "Stopping devflow services"
  docker_compose -f "$compose_file" down

  log "Docker services stopped. CLI tools (agent-deck, wt, claude/opencode) remain available."
}

devflow_status() {
  section "devflow status"

  local compose_file
  compose_file="$(devflow_compose_file)"

  # Cache docker info check once for the whole status run
  local docker_ok=false
  if has_cmd docker && timeout 5 docker info >/dev/null 2>&1; then
    docker_ok=true
  fi

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
    if $docker_ok; then
      if docker_compose -f "$compose_file" ps --status running 2>/dev/null | grep -q "hindsight"; then
        ok "Hindsight container running (Docker)"
        hindsight_runtime_found=true
      else
        fail "Hindsight container not running — run 'devflow up' to start"
      fi
    else
      fail "Docker runtime not running — run 'devflow up' to start"
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

  # ── Layer 4: Code Review ────────────────────────────────────────────────────
  printf "\n${BOLD}Layer 4: Code Review${RESET} (AI-powered)\n"
  if [[ -n "${DEVFLOW_REVIEW_CLI:-}" ]] && has_cmd "$DEVFLOW_REVIEW_CLI"; then
    ok "Code review CLI: ${DEVFLOW_REVIEW_CLI} (DEVFLOW_REVIEW_CLI override)"
  elif has_cmd claude; then
    ok "Code review CLI: claude (primary)"
  elif has_cmd opencode; then
    ok "Code review CLI: opencode (fallback)"
  else
    fail "No code review CLI found — install Claude Code or OpenCode"
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
  if $docker_ok; then
    if docker_compose -f "$compose_file" ps --status running 2>/dev/null | grep -q "langfuse"; then
      ok "Langfuse container running"
    else
      fail "Langfuse container not running — run 'devflow up' to start"
    fi
  else
    fail "Docker runtime not running — run 'devflow up' to start"
  fi

  echo ""
}

devflow_restart() {
  devflow_down "$@"
  devflow_up "$@"
}
