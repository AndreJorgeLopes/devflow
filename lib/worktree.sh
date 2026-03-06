#!/usr/bin/env bash
# devflow/lib/worktree.sh — devflow worktree implementation
# Wrapper around worktrunk (wt) for creating worktrees with optional agent launch via agent-deck.

# _detect_project_group — derive a group name from git remote or directory name
_detect_project_group() {
  local group=""

  # Try git remote origin URL first
  if git remote get-url origin >/dev/null 2>&1; then
    local url
    url="$(git remote get-url origin)"
    # Extract "org/repo" or just "repo" from SSH or HTTPS URLs
    group="$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#' | tr '/' '-')"
  fi

  # Fallback to directory name
  if [[ -z "$group" ]]; then
    group="$(basename "$(project_root)")"
  fi

  echo "$group"
}

devflow_worktree() {
  local name=""
  local agent=""
  local group=""

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
      -g|--group)
        group="${2:-}"
        [[ -z "$group" ]] && die "Usage: devflow worktree <name> -g <group>"
        shift 2
        ;;
      --group=*)
        group="${1#--group=}"
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

  [[ -z "$name" ]] && die "Usage: devflow worktree <name> [--agent claude|opencode] [-g <group>]"

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

  # Auto-detect project group if not specified and agent is requested
  if [[ -n "$agent" && -z "$group" ]]; then
    group="$(_detect_project_group)"
    detail "Auto-detected group: ${group}"
  fi

  section "Creating worktree: ${name}"

  # Step 1: Create the worktree with wt (includes copy-ignored)
  log "Running: wt step -c ${name}"
  wt step -c "$name"

  local wt_exit=$?
  if [[ $wt_exit -ne 0 ]]; then
    die "Failed to create worktree '${name}' (wt exit code: ${wt_exit})"
  fi

  ok "Worktree '${name}' created"

  # Step 2: If agent requested, register with agent-deck and launch
  if [[ -n "$agent" ]]; then
    if ! has_cmd agent-deck; then
      warn "agent-deck not installed — worktree created but agent not launched"
      info "Install agent-deck: brew install asheshgoplani/tap/agent-deck"
      return 0
    fi

    # Resolve the worktree path
    local wt_path
    wt_path="$(git worktree list --porcelain | grep "^worktree " | grep "${name}" | head -1 | sed 's/^worktree //')"

    if [[ -z "$wt_path" ]]; then
      warn "Could not detect worktree path — agent not launched"
      info "Register manually: agent-deck add <worktree-path> -c ${agent} -g ${group}"
      return 0
    fi

    info "Registering with agent-deck (agent: ${agent}, group: ${group})"
    local ad_args=("add" "$wt_path" "-c" "$agent")
    [[ -n "$group" ]] && ad_args+=("-g" "$group")

    log "Running: agent-deck ${ad_args[*]}"
    agent-deck "${ad_args[@]}"

    if [[ $? -eq 0 ]]; then
      ok "Agent session registered with agent-deck"
    else
      warn "agent-deck registration failed — worktree is still ready"
      info "Register manually: agent-deck add ${wt_path} -c ${agent} -g ${group}"
    fi
  fi

  ok "Worktree '${name}' ready"
  [[ -n "$agent" ]] && info "Launch the session with: agent-deck start ${name}"
}
