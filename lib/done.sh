#!/usr/bin/env bash
# devflow/lib/done.sh — clean up a completed work session
# Removes local worktree + branch after PR is merged.
# Remote branch is auto-deleted by GitHub (delete_branch_on_merge=true).

devflow_done() {
  local branch="${1:-}"

  if [[ -z "$branch" ]]; then
    cat <<EOF
${BOLD}Usage:${RESET} devflow done <branch-name> [options]

Clean up a completed work session: remove worktree, delete local branch,
close agent-deck session.

${BOLD}Arguments:${RESET}
  <branch-name>    The branch to clean up (e.g., feat/smart-hooks)

${BOLD}Options:${RESET}
  --force          Force cleanup even if branch is not fully merged
  -h, --help       Show this help

${BOLD}Examples:${RESET}
  devflow done feat/smart-hooks
  devflow done feat/MES-1234 --force
EOF
    return 1
  fi

  shift
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)   force=true; shift ;;
      -h|--help) devflow_done; return 0 ;;
      *)         err "Unknown option: $1"; devflow_done; return 1 ;;
    esac
  done

  section "Cleaning up: ${branch}"

  # Step 1: Close agent-deck session (if exists)
  if has_cmd agent-deck; then
    local session_match
    session_match="$(agent-deck list 2>/dev/null | grep -i "${branch}" | head -1 || true)"
    if [[ -n "$session_match" ]]; then
      local session_id
      session_id="$(echo "$session_match" | awk '{print $1}')"
      info "Closing agent-deck session: ${session_id}"
      agent-deck stop "$session_id" 2>/dev/null || true
      agent-deck remove "$session_id" 2>/dev/null || true
      ok "Agent-deck session closed"
    else
      skip "No active agent-deck session for ${branch}"
    fi
  fi

  # Step 2: Remove worktree
  local worktree_path
  worktree_path="$(git worktree list --porcelain 2>/dev/null | grep -B2 "branch refs/heads/${branch}" | grep "^worktree " | sed 's/^worktree //' || true)"

  if [[ -n "$worktree_path" ]]; then
    info "Removing worktree: ${worktree_path}"
    if [[ "$force" == "true" ]]; then
      git worktree remove "$worktree_path" --force 2>/dev/null \
        && ok "Worktree removed" \
        || warn "Could not remove worktree — remove manually: rm -rf ${worktree_path}"
    else
      git worktree remove "$worktree_path" 2>/dev/null \
        && ok "Worktree removed" \
        || { warn "Worktree has changes. Use --force to remove anyway"; return 1; }
    fi
  else
    skip "No worktree found for ${branch}"
  fi

  # Prune stale worktree references
  git worktree prune 2>/dev/null || true

  # Step 3: Delete local branch
  if git rev-parse --verify "$branch" >/dev/null 2>&1; then
    info "Deleting local branch: ${branch}"
    if [[ "$force" == "true" ]]; then
      git branch -D "$branch" 2>/dev/null \
        && ok "Local branch deleted" \
        || warn "Could not delete local branch"
    else
      git branch -d "$branch" 2>/dev/null \
        && ok "Local branch deleted (fully merged)" \
        || { warn "Branch not fully merged. Use --force to delete anyway"; return 1; }
    fi
  else
    skip "Local branch ${branch} already deleted"
  fi

  log ""
  ok "Session cleaned up: ${branch}"
  info "Remote branch is auto-deleted by GitHub when the PR is merged."
}

# devflow clean — remove all worktrees except main/master
devflow_clean() {
  local force=false
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)    force=true; shift ;;
      --dry-run)  dry_run=true; shift ;;
      -h|--help)
        cat <<EOF
${BOLD}Usage:${RESET} devflow clean [options]

Remove all worktrees and their local branches (except main/master).

${BOLD}Options:${RESET}
  --dry-run        Show what would be cleaned without doing it
  --force          Force removal even if worktrees have uncommitted changes
  -h, --help       Show this help
EOF
        return 0
        ;;
      *) err "Unknown option: $1"; return 1 ;;
    esac
  done

  section "Cleaning all worktrees"

  local main_worktree
  main_worktree="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"

  local count=0
  local branches=()

  # Collect worktrees to remove (skip the main worktree)
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
      local wt_path="${BASH_REMATCH[1]}"
      if [[ "$wt_path" == "$main_worktree" ]]; then
        continue
      fi
      local wt_branch=""
    elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]]; then
      wt_branch="${BASH_REMATCH[1]}"
      if [[ "$wt_branch" == "main" ]] || [[ "$wt_branch" == "master" ]]; then
        continue
      fi
      branches+=("${wt_branch}")
      ((count++))
      if [[ "$dry_run" == "true" ]]; then
        info "[dry-run] Would remove: ${wt_path} (${wt_branch})"
      fi
    fi
  done < <(git worktree list --porcelain 2>/dev/null)

  if [[ $count -eq 0 ]]; then
    ok "No worktrees to clean (only main worktree exists)"
    return 0
  fi

  if [[ "$dry_run" == "true" ]]; then
    log ""
    info "${count} worktree(s) would be removed. Run without --dry-run to execute."
    return 0
  fi

  info "Found ${count} worktree(s) to clean"

  for branch in "${branches[@]}"; do
    log ""
    devflow_done "$branch" $(if [[ "$force" == "true" ]]; then echo "--force"; fi) || true
  done

  git worktree prune 2>/dev/null || true

  log ""
  ok "All worktrees cleaned"
}
