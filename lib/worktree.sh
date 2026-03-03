#!/usr/bin/env bash
# devflow/lib/worktree.sh — devflow worktree implementation
# Wrapper around worktrunk (wt) for creating worktrees with optional agent launch.

devflow_worktree() {
  local name=""
  local agent=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)
        agent="${2:-}"
        [[ -z "$agent" ]] && die "Usage: devflow worktree <name> --agent <claude|opencode>"
        shift 2
        ;;
      --agent=*)
        agent="${1#--agent=}"
        shift
        ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        else
          die "Unexpected argument: $1"
        fi
        shift
        ;;
    esac
  done

  [[ -z "$name" ]] && die "Usage: devflow worktree <name> [--agent claude|opencode]"

  # Validate agent if specified
  if [[ -n "$agent" ]]; then
    case "$agent" in
      claude|opencode) ;;
      *) die "Unknown agent: $agent. Supported: claude, opencode" ;;
    esac
  fi

  # Check worktrunk is installed
  if ! has_cmd wt; then
    die "worktrunk (wt) is not installed. Run 'devflow init' or 'brew install worktrunk'."
  fi

  section "Creating worktree: ${name}"

  # Build the wt command
  local wt_args=("switch" "-c" "$name")

  if [[ -n "$agent" ]]; then
    wt_args+=("-x" "$agent")
    info "Will launch ${agent} agent after worktree creation"
  fi

  # Create worktree
  log "Running: wt ${wt_args[*]}"
  wt "${wt_args[@]}"

  # Copy ignored files to eliminate cold starts
  info "Copying ignored files to new worktree..."
  wt step copy-ignored

  ok "Worktree '${name}' ready"
}
