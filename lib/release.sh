#!/usr/bin/env bash
# devflow/lib/release.sh — Release pipeline functions
# Conventional commit parsing, semver arithmetic, version bumping.
# Sourced by bin/devflow.

# ── Conventional Commit Parser ───────────────────────────────────────────────

# _parse_conventional_commits [project_dir]
# Parses commits since last tag to determine version bump type.
# Output line 1: bump type (major/minor/patch/none)
# Output lines 2+: categorized commit messages (CATEGORY|message)
_parse_conventional_commits() {
  local project_dir="${1:-.}"

  # Get last tag
  local last_tag
  last_tag="$(git -C "$project_dir" describe --tags --abbrev=0 2>/dev/null || echo "")"

  # Determine commit range
  local range
  if [[ -n "$last_tag" ]]; then
    range="${last_tag}..HEAD"
  else
    # No previous tag — scan from initial commit
    local initial_commit
    initial_commit="$(git -C "$project_dir" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)"
    range="${initial_commit}..HEAD"
  fi

  # Get full commit messages (subject + body)
  local commits
  commits="$(git -C "$project_dir" log "$range" --format='%B---COMMIT_SEP---' 2>/dev/null || echo "")"
  if [[ -z "$commits" ]]; then
    echo "none"
    return 0
  fi

  # Check for [skip release] in the HEAD commit only (not the entire range)
  local head_msg
  head_msg="$(git -C "$project_dir" log -1 --format='%B' 2>/dev/null || echo "")"
  if echo "$head_msg" | grep -qi '\[skip release\]'; then
    echo "none"
    return 0
  fi

  local bump="none"
  local feat_msgs=""
  local fix_msgs=""
  local other_msgs=""

  # Parse each commit
  local IFS_SAVE="$IFS"
  while IFS= read -r -d '' commit_block; do
    [[ -z "$commit_block" ]] && continue
    local subject
    subject="$(echo "$commit_block" | head -1)"

    # Check for breaking changes (major)
    if [[ "$subject" == *"!"*":"* ]] || echo "$commit_block" | grep -q "^BREAKING CHANGE:"; then
      bump="major"
    fi

    # Categorize by prefix
    case "$subject" in
      feat:*|feat\(*)
        [[ "$bump" != "major" ]] && bump="minor"
        feat_msgs+="feat|${subject}\n"
        ;;
      fix:*|fix\(*)
        [[ "$bump" == "none" ]] && bump="patch"
        fix_msgs+="fix|${subject}\n"
        ;;
      docs:*|chore:*|refactor:*|test:*|ci:*|style:*|perf:*)
        other_msgs+="other|${subject}\n"
        ;;
    esac
  done < <(echo "$commits" | sed 's/---COMMIT_SEP---/\x00/g')
  IFS="$IFS_SAVE"

  # Output
  echo "$bump"
  [[ -n "$feat_msgs" ]] && printf "%b" "$feat_msgs"
  [[ -n "$fix_msgs" ]] && printf "%b" "$fix_msgs"
  [[ -n "$other_msgs" ]] && printf "%b" "$other_msgs"
}

# ── Semver Arithmetic ────────────────────────────────────────────────────────

# _semver_bump <current_version> <bump_type>
# Returns the new version after applying the bump.
# Exit 1 if bump_type is "none".
_semver_bump() {
  local current="$1"
  local bump_type="$2"

  if [[ "$bump_type" == "none" ]]; then
    echo "No version bump needed" >&2
    return 1
  fi

  local major minor patch
  IFS='.' read -r major minor patch <<< "$current"

  case "$bump_type" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *)     echo "Unknown bump type: $bump_type" >&2; return 1 ;;
  esac
}
