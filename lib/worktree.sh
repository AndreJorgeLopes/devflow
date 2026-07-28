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

# _expected_worktree_root — the configured worktree root (the literal prefix of
# worktrunk's worktree-path template), so devflow never hardcodes a personal path.
# Prints the absolute root, or nothing if it can't be determined.
_expected_worktree_root() {
  local cfg="${HOME}/.config/worktrunk/config.toml"
  [[ -f "$cfg" ]] || return 0
  local tmpl prefix
  tmpl="$(grep -E '^[[:space:]]*worktree-path[[:space:]]*=' "$cfg" 2>/dev/null | head -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/^"//; s/"[[:space:]]*$//')"
  [[ -n "$tmpl" ]] || return 0
  prefix="${tmpl%%\{\{*}"       # everything before the first {{ placeholder
  prefix="${prefix%/}"           # drop a trailing slash
  prefix="${prefix/#\~/$HOME}"   # expand a leading ~
  [[ -n "$prefix" ]] && echo "$prefix"
}

# _fix_worktree_location — worktrunk sometimes silently ignores the configured
# worktree-path template and drops the new worktree as a sibling of the repo. Detect
# that and move it under the configured root as <root>/<repo>/<branch-slug>.
_fix_worktree_location() {
  local branch="$1"
  local root
  root="$(_expected_worktree_root)"
  if [[ -z "$root" ]]; then
    warn "Could not read worktrunk's worktree-path; skipping location check."
    return 0
  fi
  local actual
  actual="$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/${branch}" '
    /^worktree /{ $1=""; sub(/^ /,""); w=$0 } /^branch /{ if ($2==b) print w }')"
  [[ -n "$actual" ]] || return 0
  case "$actual" in
    "$root"/*) return 0 ;;   # already under the configured root — nothing to do
  esac
  local common repo slug want
  common="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)"
  repo="$(basename "$(dirname "$common")")"
  slug="$(printf '%s' "$branch" | tr '/' '-')"
  want="${root}/${repo}/${slug}"
  [[ "$actual" == "$want" ]] && return 0
  warn "worktrunk placed the worktree outside ${root}:"
  warn "  ${actual}"
  mkdir -p "$(dirname "$want")" 2>/dev/null
  if git worktree move "$actual" "$want" 2>/dev/null; then
    ok "Corrected worktree location -> ${want}"
  else
    warn "Auto-correct failed. Move it manually:"
    warn "  git worktree move '${actual}' '${want}'"
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

  # worktrunk occasionally ignores the configured worktree-path and drops the worktree
  # as a sibling of the repo — detect that and correct it under the configured root.
  _fix_worktree_location "$branch"

  ok "Worktree '${name}' ready"
}
