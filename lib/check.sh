#!/usr/bin/env bash
# devflow/lib/check.sh — devflow check implementation
# Runs Continue.dev checks against the current branch diff.

devflow_check() {
  section "Running code checks"

  if ! has_cmd cn; then
    warn "Continue.dev CLI (cn) is not installed."
    log ""
    log "Install it with:"
    detail "npm install -g @anthropic/continue"
    log ""
    log "Or run 'devflow init' to set up all tools."
    return 1
  fi

  local proj
  proj="$(project_root)"

  # Check if .continue/checks exists
  if [[ ! -d "${proj}/.continue/checks" ]]; then
    warn "No .continue/checks/ directory found in project."
    detail "Run 'devflow init' to copy check templates."
    return 1
  fi

  log "Running cn check in ${proj}..."
  (cd "$proj" && cn check)
}
