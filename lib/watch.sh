#!/usr/bin/env bash
# devflow/lib/watch.sh — Sensitive file watchdog
# Detects stale files after code changes and notifies/fixes.
# Sourced by bin/devflow.

# ── Config Parser ────────────────────────────────────────────────────────────

# parse_sensitive_config <conf_file>
# Parses .devflow/sensitive-files.conf into normalized pipe-delimited lines.
# Output: one line per entry: CHECK_TYPE|TARGET|SOURCES|CMD_OR_PROMPT
# Strips whitespace around pipes, skips comments and blank lines.
parse_sensitive_config() {
  local conf_file="$1"

  if [[ ! -f "$conf_file" ]]; then
    return 0
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip lines starting with # (comment lines) and blank lines
    local trimmed
    trimmed="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == \#* ]] && continue
    line="$trimmed"

    # Normalize: strip whitespace around pipes
    local check_type target sources cmd_or_prompt
    IFS='|' read -r check_type target sources cmd_or_prompt <<< "$line"
    check_type="$(echo "$check_type" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    target="$(echo "$target" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    sources="$(echo "$sources" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    cmd_or_prompt="$(echo "$cmd_or_prompt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    echo "${check_type}|${target}|${sources}|${cmd_or_prompt}"
  done < "$conf_file"
}

# ── Pattern Matcher ──────────────────────────────────────────────────────────

# match_sources <sources_csv> <changed_files>
# Returns 0 if any changed file matches any source pattern.
# <sources_csv>: comma-separated glob patterns (e.g., "lib/*.sh,Makefile")
# <changed_files>: newline-separated list of changed file paths
match_sources() {
  local sources_csv="$1"
  local changed_files="$2"

  # Split sources by comma
  local IFS=','
  local patterns
  read -ra patterns <<< "$sources_csv"

  while IFS= read -r changed_file; do
    [[ -z "$changed_file" ]] && continue
    for pattern in "${patterns[@]}"; do
      pattern="$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      # Use bash pattern matching (glob)
      # shellcheck disable=SC2254
      if [[ "$changed_file" == $pattern ]]; then
        return 0
      fi
    done
  done <<< "$changed_files"

  return 1
}

# get_flagged_targets <conf_file> <changed_files>
# Returns config entries whose sources match the changed files.
# Output: same pipe-delimited format as parse_sensitive_config
get_flagged_targets() {
  local conf_file="$1"
  local changed_files="$2"
  local entries

  entries="$(parse_sensitive_config "$conf_file")"
  [[ -z "$entries" ]] && return 0

  while IFS='|' read -r check_type target sources cmd_or_prompt; do
    if match_sources "$sources" "$changed_files"; then
      echo "${check_type}|${target}|${sources}|${cmd_or_prompt}"
    fi
  done <<< "$entries"
}

# ── Version Checker ──────────────────────────────────────────────────────────

# check_version_consistency [project_dir]
# Compares version in Makefile against all version-bearing files.
# Exit 0 if all match, exit 1 if any differ (prints mismatches to stderr).
check_version_consistency() {
  local proj="${1:-.}"
  local makefile_version
  local mismatches=0

  # Extract authoritative version from Makefile
  makefile_version="$(grep '^VERSION' "$proj/Makefile" | head -1 | cut -d= -f2 | tr -d ' ')"
  if [[ -z "$makefile_version" ]]; then
    echo "ERROR: Could not extract VERSION from $proj/Makefile" >&2
    return 1
  fi

  # Check lib/utils.sh
  if [[ -f "$proj/lib/utils.sh" ]]; then
    local utils_ver
    utils_ver="$(grep 'DEVFLOW_VERSION=' "$proj/lib/utils.sh" | head -1 | cut -d'"' -f2)"
    if [[ "$utils_ver" != "$makefile_version" ]]; then
      echo "MISMATCH: lib/utils.sh has $utils_ver (expected $makefile_version)" >&2
      mismatches=$((mismatches + 1))
    fi
  fi

  # Check plugin.json
  if [[ -f "$proj/devflow-plugin/.claude-plugin/plugin.json" ]]; then
    local pj_ver
    pj_ver="$(grep '"version"' "$proj/devflow-plugin/.claude-plugin/plugin.json" | head -1 | cut -d'"' -f4)"
    if [[ "$pj_ver" != "$makefile_version" ]]; then
      echo "MISMATCH: plugin.json has $pj_ver (expected $makefile_version)" >&2
      mismatches=$((mismatches + 1))
    fi
  fi

  # Check marketplace.json
  if [[ -f "$proj/devflow-plugin/.claude-plugin/marketplace.json" ]]; then
    local mj_ver
    mj_ver="$(grep -E '^\s*"version"' "$proj/devflow-plugin/.claude-plugin/marketplace.json" | head -1 | cut -d'"' -f4)"
    if [[ -z "$mj_ver" ]]; then
      # Fallback: extract from metadata line if version is inline
      mj_ver="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('metadata',{}).get('version','') or d.get('plugins',[{}])[0].get('version',''))" "$proj/devflow-plugin/.claude-plugin/marketplace.json" 2>/dev/null || echo "")"
    fi
    if [[ -n "$mj_ver" ]] && [[ "$mj_ver" != "$makefile_version" ]]; then
      echo "MISMATCH: marketplace.json has $mj_ver (expected $makefile_version)" >&2
      mismatches=$((mismatches + 1))
    fi
  fi

  # Check command description badges
  local cmd_file
  for cmd_file in "$proj"/devflow-plugin/commands/*.md; do
    [[ -f "$cmd_file" ]] || continue
    local badge_ver
    badge_ver="$(grep '\[devflow v' "$cmd_file" | head -1 | sed 's/.*\[devflow v//;s/\].*//')"
    if [[ -n "$badge_ver" ]] && [[ "$badge_ver" != "$makefile_version" ]]; then
      echo "MISMATCH: $(basename "$cmd_file") badge has $badge_ver (expected $makefile_version)" >&2
      mismatches=$((mismatches + 1))
    fi
  done

  if [[ "$mismatches" -gt 0 ]]; then
    echo "$mismatches version mismatch(es) found. Authoritative version: $makefile_version" >&2
    return 1
  fi

  echo "All versions consistent: $makefile_version"
  return 0
}
