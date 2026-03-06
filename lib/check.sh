#!/usr/bin/env bash
# devflow/lib/check.sh — devflow check implementation
# Multi-CLI code review abstraction.
# Uses Claude Code CLI (primary) or OpenCode CLI (fallback) to run
# AI-powered code review against .devflow/checks/*.md rule files.

# ── CLI Detection ─────────────────────────────────────────────────────────────

# _detect_review_cli — determine which review CLI to use
# Priority: DEVFLOW_REVIEW_CLI env var > claude > opencode
_detect_review_cli() {
  if [[ -n "${DEVFLOW_REVIEW_CLI:-}" ]]; then
    if has_cmd "$DEVFLOW_REVIEW_CLI"; then
      echo "$DEVFLOW_REVIEW_CLI"
      return 0
    else
      warn "DEVFLOW_REVIEW_CLI='${DEVFLOW_REVIEW_CLI}' not found on PATH"
      return 1
    fi
  fi

  if has_cmd claude; then
    echo "claude"
    return 0
  fi

  if has_cmd opencode; then
    echo "opencode"
    return 0
  fi

  return 1
}

# ── Check Rules Collection ────────────────────────────────────────────────────

# _collect_check_rules <project_dir> — read and concatenate all .devflow/checks/*.md
# Outputs the combined rules text to stdout.
_collect_check_rules() {
  local proj="$1"
  local checks_dir="${proj}/.devflow/checks"
  local rules=""
  local count=0

  if [[ ! -d "$checks_dir" ]]; then
    return 1
  fi

  for check_file in "${checks_dir}"/*.md; do
    [[ -f "$check_file" ]] || continue
    local name
    name="$(basename "$check_file" .md)"
    rules+="$(printf '\n\n--- CHECK RULE: %s ---\n' "$name")"
    rules+="$(cat "$check_file")"
    ((count++))
  done

  if [[ $count -eq 0 ]]; then
    return 1
  fi

  info "Loaded ${count} check rule(s) from .devflow/checks/"
  echo "$rules"
}

# ── Claude Code Path ──────────────────────────────────────────────────────────

# _run_review_claude <rules> <diff>
# Uses claude --print with system prompt for structured review.
_run_review_claude() {
  local rules="$1"
  local diff="$2"

  local system_prompt
  system_prompt="$(cat <<'SYSPROMPT'
You are a code reviewer. Review the git diff provided against the check rules below.
For each rule, assess whether the diff introduces violations.

Output format:
For each check rule, output:
  ## <rule-name>
  **Result:** PASS | FAIL | N/A
  **Details:** <specific findings or "No violations found">

If a rule doesn't apply to the changed files, mark it N/A.
Be specific — reference file names and line numbers from the diff.
At the end, output a summary line:
  **Overall:** PASS (if all rules pass or are N/A) | FAIL (if any rule fails)

SYSPROMPT
)"
  system_prompt+="$rules"

  echo "$diff" | claude --print \
    --system-prompt "$system_prompt" \
    --permission-mode plan \
    --allowedTools "Read,Glob,Grep" \
    "Review this git diff against the check rules in your system prompt." \
    2>/dev/null
}

# ── OpenCode Path ─────────────────────────────────────────────────────────────

# _run_review_opencode <rules> <diff>
# Uses opencode run with combined prompt (rules + diff in single message).
_run_review_opencode() {
  local rules="$1"
  local diff="$2"

  local prompt
  prompt="$(cat <<OCPROMPT
You are a code reviewer. Review the following git diff against the check rules provided.

For each rule, assess whether the diff introduces violations.

Output format:
For each check rule, output:
  ## <rule-name>
  **Result:** PASS | FAIL | N/A
  **Details:** <specific findings or "No violations found">

If a rule doesn't apply to the changed files, mark it N/A.
Be specific — reference file names and line numbers from the diff.
At the end, output a summary line:
  **Overall:** PASS (if all rules pass or are N/A) | FAIL (if any rule fails)

--- CHECK RULES ---
${rules}

--- GIT DIFF ---
${diff}
OCPROMPT
)"

  opencode run "$prompt" 2>/dev/null
}

# ── Main Entry Point ──────────────────────────────────────────────────────────

devflow_check() {
  section "Running code review checks"

  # 1. Detect review CLI
  local review_cli
  review_cli="$(_detect_review_cli)" || {
    warn "No review CLI available."
    log ""
    log "Install one of:"
    detail "claude  — Claude Code CLI (recommended)"
    detail "opencode — OpenCode CLI"
    log ""
    log "Or set DEVFLOW_REVIEW_CLI to a custom review command."
    return 1
  }
  ok "Using review CLI: ${review_cli}"

  # 2. Find project root
  local proj
  proj="$(project_root)"

  # 3. Collect check rules
  local rules
  rules="$(_collect_check_rules "$proj")" || {
    warn "No .devflow/checks/ directory or no check rules found in project."
    detail "Run 'devflow init' to copy check templates."
    return 1
  }

  # 4. Get git diff
  local diff
  diff="$(git -C "$proj" diff HEAD 2>/dev/null || echo "")"

  if [[ -z "$diff" ]]; then
    info "No uncommitted changes — checking staged changes..."
    diff="$(git -C "$proj" diff --cached 2>/dev/null || echo "")"
  fi

  if [[ -z "$diff" ]]; then
    warn "No changes to review (no uncommitted or staged changes)."
    return 0
  fi

  # 5. Dispatch to appropriate CLI
  log "Running review with ${review_cli}..."
  local result
  case "$review_cli" in
    claude)
      result="$(_run_review_claude "$rules" "$diff")" || {
        err "Claude Code review failed."
        warn "Make sure Claude Code is installed and authenticated."
        return 1
      }
      ;;
    opencode)
      result="$(_run_review_opencode "$rules" "$diff")" || {
        err "OpenCode review failed."
        warn "Make sure OpenCode is installed and authenticated."
        return 1
      }
      ;;
    *)
      # Custom CLI via DEVFLOW_REVIEW_CLI — pass rules and diff as arguments
      result="$(echo "$diff" | "$review_cli" "$rules" 2>/dev/null)" || {
        err "Review CLI '${review_cli}' failed."
        return 1
      }
      ;;
  esac

  # 6. Output results
  echo ""
  echo "$result"
  echo ""

  # 7. Check for overall pass/fail
  if echo "$result" | grep -qi "Overall.*FAIL"; then
    err "Code review: FAIL"
    return 1
  elif echo "$result" | grep -qi "Overall.*PASS"; then
    ok "Code review: PASS"
    return 0
  else
    info "Review complete (could not determine pass/fail from output)"
    return 0
  fi
}
