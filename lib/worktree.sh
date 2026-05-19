#!/usr/bin/env bash
# devflow/lib/worktree.sh — devflow worktree implementation
# Wrapper around worktrunk (wt) for creating worktrees.

# _ensure_main_unlocked — detach any worktree that has main/master checked out
# Git only allows one worktree per branch. If main is checked out somewhere,
# no other worktree can use it. Detaching frees the branch name without losing
# any work (files stay the same, just HEAD becomes detached).
_ensure_main_unlocked() {
  local main_branch="main"
  if ! git rev-parse --verify "$main_branch" >/dev/null 2>&1; then
    main_branch="master"
    if ! git rev-parse --verify "$main_branch" >/dev/null 2>&1; then
      return 0  # No main/master branch, nothing to unlock
    fi
  fi

  # Find which worktree (if any) has main checked out
  local locked_wt
  locked_wt="$(git worktree list --porcelain | grep -B1 "branch refs/heads/${main_branch}" | grep "^worktree " | sed 's/^worktree //')" || true

  if [[ -z "$locked_wt" ]]; then
    return 0  # main is not checked out anywhere
  fi

  # Detach that worktree so main is freed
  info "Detaching ${locked_wt} from ${main_branch} (freeing branch for worktree operations)"
  git -C "$locked_wt" checkout --detach 2>/dev/null || true
}

# _normalize_branch_name — turn user-supplied name into a ticket-shaped branch
# - "MES-1234" or "MES-1234-add-foo" → keep as-is (already ticket-shaped)
# - "mes-1234" → keep as-is (case-insensitive — supports lowercase JIRA prefixes)
# - "feat/already-prefixed" → keep as-is (any slash-containing name passes through)
# - "add-user-metrics" → "feat/add-user-metrics"
# - empty → die (handled upstream by usage check)
#
# Note: case-insensitive regex is deliberate (issue #28: BUG-3 fix). It also matches
# "wip-2-thing" / "feat-1234-cleanup" style names that look ticket-ish — those are
# treated as deliberate branch names (no prefix added). If you actually want a "feat/"
# prefix on a name like that, drop the digits or use a different word.
_normalize_branch_name() {
  local raw="$1"
  # Already-prefixed (contains "/") or ticket-shaped (case-insensitive PREFIX-NUMBER) → pass through.
  # Otherwise prefix with "feat/".
  if [[ "$raw" == */* ]] || [[ "$raw" =~ ^[A-Za-z]+-[0-9]+ ]]; then
    echo "$raw"
  else
    echo "feat/$raw"
  fi
}

devflow_worktree() {
  local name=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)
        die "--agent flag removed: agent-deck is no longer wired into devflow. Use 'devflow worktree <name>' without --agent."
        ;;
      --agent=*)
        die "--agent flag removed: agent-deck is no longer wired into devflow. Use 'devflow worktree <name>' without --agent."
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

  [[ -z "$name" ]] && die "Usage: devflow worktree <name>"

  # Check worktrunk is installed
  if ! has_cmd wt; then
    die "worktrunk (wt) is not installed. Run 'devflow init' or 'brew install worktrunk'."
  fi

  section "Creating worktree: ${name}"

  # Ensure main/master isn't locked by another worktree (detach if needed)
  _ensure_main_unlocked

  # Create the worktree with wt
  local branch
  branch="$(_normalize_branch_name "$name")"
  log "Running: wt switch --create ${branch}"
  local wt_exit=0
  wt switch --create "$branch" || wt_exit=$?
  if [[ $wt_exit -ne 0 ]]; then
    die "Failed to create worktree '${name}' (wt exit code: ${wt_exit})"
  fi

  ok "Worktree '${name}' ready"
}
