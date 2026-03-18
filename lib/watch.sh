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
