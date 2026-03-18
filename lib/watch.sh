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
