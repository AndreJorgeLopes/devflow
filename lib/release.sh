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

  # Determine log target
  local log_target
  if [[ -n "$last_tag" ]]; then
    log_target="${last_tag}..HEAD"
  else
    # No previous tag — scan all commits reachable from HEAD, including root
    log_target="HEAD"
  fi

  # Stream commits with NUL separators using git's %x00 (portable, no bash NUL issues)
  local commits
  commits="$(git -C "$project_dir" log "$log_target" --format='%B%x00' 2>/dev/null || echo "")"
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

    # Categorize by prefix (including breaking ! variants)
    case "$subject" in
      feat:*|feat!:*|feat\(*)
        [[ "$bump" != "major" ]] && bump="minor"
        feat_msgs+="feat|${subject}\n"
        ;;
      fix:*|fix!:*|fix\(*)
        [[ "$bump" == "none" ]] && bump="patch"
        fix_msgs+="fix|${subject}\n"
        ;;
      docs:*|docs!:*|chore:*|chore!:*|refactor:*|refactor!:*|test:*|test!:*|ci:*|ci!:*|style:*|style!:*|perf:*|perf!:*)
        other_msgs+="other|${subject}\n"
        ;;
    esac
  done < <(printf '%s' "$commits")
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

# ── Version Bump ─────────────────────────────────────────────────────────────

# bump_all_versions <new_version> [project_dir]
# Updates all version-bearing files to the new version using sed.
# This is the write-side counterpart to check_version_consistency (read-side).
bump_all_versions() {
  local new_version="$1"
  local proj="${2:-.}"

  # Portable sed -i wrapper (works on both macOS and GNU/Linux)
  _sed_inplace() {
    local pattern="$1" file="$2"
    sed "$pattern" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  }

  # Makefile: VERSION := X.Y.Z
  if [[ -f "$proj/Makefile" ]]; then
    _sed_inplace "s/^VERSION := .*/VERSION := ${new_version}/" "$proj/Makefile"
  fi

  # lib/utils.sh: DEVFLOW_VERSION="X.Y.Z"
  if [[ -f "$proj/lib/utils.sh" ]]; then
    _sed_inplace "s/DEVFLOW_VERSION=\"[^\"]*\"/DEVFLOW_VERSION=\"${new_version}\"/" "$proj/lib/utils.sh"
  fi

  # plugin.json: "version": "X.Y.Z"
  if [[ -f "$proj/devflow-plugin/.claude-plugin/plugin.json" ]]; then
    _sed_inplace "s/\"version\": \"[^\"]*\"/\"version\": \"${new_version}\"/" "$proj/devflow-plugin/.claude-plugin/plugin.json"
  fi

  # marketplace.json: "version": "X.Y.Z"
  if [[ -f "$proj/devflow-plugin/.claude-plugin/marketplace.json" ]]; then
    _sed_inplace "s/\"version\": \"[^\"]*\"/\"version\": \"${new_version}\"/" "$proj/devflow-plugin/.claude-plugin/marketplace.json"
  fi

  # Command description badges: [devflow vX.Y.Z]
  local cmd_file
  for cmd_file in "$proj"/devflow-plugin/commands/*.md; do
    [[ -f "$cmd_file" ]] || continue
    _sed_inplace "s/\[devflow v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\]/[devflow v${new_version}]/" "$cmd_file"
  done

  echo "All version files updated to ${new_version}"
}

# ── CLI Commands ─────────────────────────────────────────────────────────────

# devflow_version_bump <new_version>
# CLI wrapper for bump_all_versions with validation.
devflow_version_bump() {
  local new_version="${1:?Usage: devflow version-bump <new_version>}"
  local proj
  proj="$(project_root)"

  section "Bumping version to ${new_version}"
  bump_all_versions "$new_version" "$proj"
  check_version_consistency "$proj" && ok "Version consistency validated"
}

# devflow_release_preview
# Shows what the next release would look like without creating it.
devflow_release_preview() {
  local proj
  proj="$(project_root)"

  section "Release Preview"

  # Current version
  local current_version
  current_version="$(grep '^VERSION' "$proj/Makefile" | head -1 | cut -d= -f2 | tr -d ' ')"
  info "Current version: v${current_version}"

  # Parse commits
  local parse_output
  parse_output="$(_parse_conventional_commits "$proj")"
  local bump_type
  bump_type="$(echo "$parse_output" | head -1)"

  if [[ "$bump_type" == "none" ]]; then
    info "No releasable commits since last tag. Nothing to release."
    return 0
  fi

  # Compute new version
  local new_version
  new_version="$(_semver_bump "$current_version" "$bump_type")"
  ok "Next version: v${new_version} (${bump_type} bump)"

  # Show categorized commits
  echo ""
  info "Commits to include:"
  echo "$parse_output" | tail -n +2 | while IFS='|' read -r category msg; do
    case "$category" in
      feat)  echo "  ${GREEN}feat${RESET}: $msg" ;;
      fix)   echo "  ${YELLOW}fix${RESET}: $msg" ;;
      other) echo "  ${DIM}$msg${RESET}" ;;
    esac
  done

  # Validate current version consistency
  echo ""
  if check_version_consistency "$proj" >/dev/null 2>&1; then
    ok "Version files are consistent"
  else
    fail "Version files are inconsistent — run 'devflow check-version' for details"
  fi
}
