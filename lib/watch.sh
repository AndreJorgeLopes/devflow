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

# ── Notification ─────────────────────────────────────────────────────────────

# _watch_notify <message> [--headless]
# Send notification via platform-appropriate method.
_watch_notify() {
  local message="$1"
  local headless="${2:-}"

  # Always log
  local log_dir="${HOME}/.devflow"
  mkdir -p "$log_dir"
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $message" >> "${log_dir}/watch.log"

  if [[ "$headless" == "--headless" ]]; then
    # Cron mode — OS-native notifications only
    case "$(uname -s)" in
      Darwin)
        osascript -e "display notification \"$message\" with title \"devflow watchdog\"" 2>/dev/null || true
        ;;
      Linux)
        if command -v notify-send >/dev/null 2>&1; then
          notify-send "devflow watchdog" "$message" 2>/dev/null || true
        fi
        ;;
    esac
  else
    # Interactive mode — terminal bell + stderr
    printf '\a' 2>/dev/null || true
    warn "$message"
  fi
}

# _write_pending_json <file> <entries_json>
# Write or append to a pending JSON file.
_write_pending_json() {
  local file="$1"
  local entry="$2"
  local dir
  dir="$(dirname "$file")"
  mkdir -p "$dir"

  if [[ -f "$file" ]]; then
    # Append to existing array
    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data.append(json.loads(sys.argv[2]))
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
" "$file" "$entry" 2>/dev/null || echo "[$entry]" > "$file"
  else
    echo "[$entry]" > "$file"
  fi
}

# ── Auto-Reinstall ───────────────────────────────────────────────────────────

# _detect_install_mode
# Detects how devflow is installed: link (symlink), install (copy), brew, or none.
_detect_install_mode() {
  local devflow_path
  devflow_path="$(command -v devflow 2>/dev/null || echo "")"
  [[ -z "$devflow_path" ]] && echo "none" && return

  # Resolve the real path for Homebrew detection
  local resolved_path
  resolved_path="$(readlink -f "$devflow_path" 2>/dev/null || readlink "$devflow_path" 2>/dev/null || echo "$devflow_path")"

  # Check for Homebrew paths
  if [[ "$resolved_path" == */opt/homebrew/* ]] || \
     [[ "$resolved_path" == */usr/local/Cellar/* ]] || \
     [[ "$resolved_path" == */home/linuxbrew/* ]] || \
     [[ "$resolved_path" == */Cellar/* ]]; then
    echo "brew"
    return
  fi

  # Check if it's a symlink (make link)
  if [[ -L "$devflow_path" ]]; then
    echo "link"
  else
    echo "install"
  fi
}

# _auto_reinstall_check <project_dir> <origin_sha> <headless> [dry_run]
# Checks if local devflow install is stale and updates it.
# Only runs if auto_reinstall=true in .devflow/.dev-setup.
_auto_reinstall_check() {
  local project_dir="$1"
  local origin_sha="$2"
  local headless="${3:-}"
  local dry_run="${4:-}"

  # Guard: check opt-in
  local setup_file="${project_dir}/.devflow/.dev-setup"
  if [[ ! -f "$setup_file" ]] || ! grep -q "auto_reinstall=true" "$setup_file" 2>/dev/null; then
    return 0
  fi

  # Compare installed SHA against origin/main SHA
  local sha_file="${HOME}/.devflow/.last-installed-sha"
  local last_installed_sha=""
  if [[ -f "$sha_file" ]]; then
    last_installed_sha="$(cat "$sha_file")"
  fi

  if [[ "$last_installed_sha" == "$origin_sha" ]]; then
    return 0  # Already up to date
  fi

  # Detect install mode
  local install_mode
  install_mode="$(_detect_install_mode)"

  local make_target=""
  case "$install_mode" in
    link)    make_target="link" ;;
    install) make_target="install" ;;
    brew)
      _watch_notify "devflow is managed by Homebrew. Run: brew upgrade devflow" "$headless"
      return 0
      ;;
    none)    return 0 ;;
  esac

  # Dry-run support
  local old_sha_short="${last_installed_sha:0:7}"
  local new_sha_short="${origin_sha:0:7}"

  if [[ -n "$dry_run" ]]; then
    echo "DRY RUN — Would run make ${make_target} (installed SHA: ${old_sha_short}, origin/main: ${new_sha_short})"
    return 0
  fi

  # Run make target, capture output for error logging
  local make_output
  if make_output="$(cd "$project_dir" && make "$make_target" 2>&1)"; then
    mkdir -p "${HOME}/.devflow"
    echo "$origin_sha" > "$sha_file"
    _watch_notify "devflow auto-updated ${old_sha_short}..${new_sha_short} (via make ${make_target})" "$headless"
  else
    local make_rc=$?
    # Log full make output for debugging
    mkdir -p "${HOME}/.devflow"
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] make ${make_target} FAILED output:" >> "${HOME}/.devflow/watch.log"
    echo "$make_output" >> "${HOME}/.devflow/watch.log"
    _watch_notify "devflow auto-update FAILED: make ${make_target} exited with code ${make_rc}" "$headless"
    # Do NOT update SHA — next cron run will retry
  fi
}

# ── Watcher Core ─────────────────────────────────────────────────────────────

# devflow_watch [setup|remove] [--headless] [--immediate] [--dry-run] [--derive-config]
devflow_watch() {
  local subcmd=""
  local headless=""
  local immediate=""
  local dry_run=""
  local derive_config=""
  local project_dir=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      setup)          subcmd="setup"; shift ;;
      remove)         subcmd="remove"; shift ;;
      --headless)     headless="--headless"; shift ;;
      --immediate)    immediate="1"; shift ;;
      --dry-run)      dry_run="1"; shift ;;
      --derive-config) derive_config="1"; shift ;;
      --project)      project_dir="$2"; shift 2 ;;
      *)              warn "Unknown option: $1"; shift ;;
    esac
  done

  # Route subcommands
  case "$subcmd" in
    setup)  _watch_setup "$project_dir" ;;
    remove) _watch_remove "$project_dir" ;;
    "")     _watch_run "$project_dir" "$headless" "$immediate" "$dry_run" ;;
  esac
}

# _watch_run — core watcher logic
_watch_run() {
  local project_dir="${1:-$(pwd)}"
  local headless="${2:-}"
  local immediate="${3:-}"
  local dry_run="${4:-}"

  local conf_file="${project_dir}/.devflow/sensitive-files.conf"

  # Step 0: Check config exists
  if [[ ! -f "$conf_file" ]]; then
    [[ -n "$headless" ]] || info "No sensitive-files.conf found, skipping."
    return 0
  fi

  # Step 1: Fetch (unless --immediate)
  if [[ -z "$immediate" ]]; then
    git -C "$project_dir" fetch origin main --quiet 2>/dev/null || true
  fi

  # Step 2: Compare SHAs
  local local_sha origin_sha
  local_sha="$(git -C "$project_dir" rev-parse main 2>/dev/null || echo "")"
  origin_sha="$(git -C "$project_dir" rev-parse origin/main 2>/dev/null || echo "")"

  if [[ -z "$local_sha" ]] || [[ -z "$origin_sha" ]]; then
    return 0
  fi

  # Check last-checked SHA to avoid re-processing
  local sha_file="${project_dir}/.devflow/.last-checked-sha"
  if [[ -f "$sha_file" ]]; then
    local last_checked
    last_checked="$(cat "$sha_file")"
    if [[ "$last_checked" == "$origin_sha" ]]; then
      return 0
    fi
  fi

  if [[ "$local_sha" == "$origin_sha" ]]; then
    # Update tracking and exit
    mkdir -p "$(dirname "$sha_file")"
    echo "$origin_sha" > "$sha_file"
    return 0
  fi

  # Step 3: Get changed files
  local changed_files
  changed_files="$(git -C "$project_dir" diff --name-only "${local_sha}..${origin_sha}" 2>/dev/null || echo "")"
  if [[ -z "$changed_files" ]]; then
    mkdir -p "$(dirname "$sha_file")"
    echo "$origin_sha" > "$sha_file"
    return 0
  fi

  # Step 4: Match against config
  local flagged
  flagged="$(get_flagged_targets "$conf_file" "$changed_files")"
  if [[ -z "$flagged" ]]; then
    mkdir -p "$(dirname "$sha_file")"
    echo "$origin_sha" > "$sha_file"
    return 0
  fi

  if [[ -n "$dry_run" ]]; then
    echo "DRY RUN — Flagged targets:"
    echo "$flagged" | while IFS='|' read -r ctype target sources cmd; do
      echo "  [$ctype] $target (sources: $sources)"
    done
    return 0
  fi

  # Step 5-6: Run checks in parallel
  local mechanical_stale=""
  local semantic_flagged=""
  local pids=()
  local result_dir="${TMPDIR:-/tmp}/devflow-watch-$$"
  mkdir -p "$result_dir"

  while IFS='|' read -r check_type target sources cmd_or_prompt; do
    if [[ "$check_type" == "mechanical" ]]; then
      (
        cd "$project_dir"
        if ! eval "$cmd_or_prompt" >/dev/null 2>&1; then
          echo "$target" >> "${result_dir}/mechanical_stale"
        fi
      ) &
      pids+=($!)
    elif [[ "$check_type" == "semantic" ]]; then
      echo "${target}|${cmd_or_prompt}" >> "${result_dir}/semantic_flagged"
    fi
  done <<< "$flagged"

  # Wait for all parallel mechanical checks
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Step 7-8: Record results
  local pending_dir="${project_dir}/.devflow"
  mkdir -p "$pending_dir"
  local issues_found=0

  if [[ -f "${result_dir}/mechanical_stale" ]]; then
    while IFS= read -r stale_target; do
      local entry_json
      entry_json="$(python3 -c "import json,sys; print(json.dumps({'target': sys.argv[1], 'type': 'mechanical', 'detected_at': sys.argv[2]}))" "$stale_target" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
      _write_pending_json "${pending_dir}/pending-fixes.json" "$entry_json"
      issues_found=$((issues_found + 1))
    done < "${result_dir}/mechanical_stale"
  fi

  if [[ -f "${result_dir}/semantic_flagged" ]]; then
    while IFS='|' read -r sem_target sem_prompt; do
      local entry_json
      entry_json="$(python3 -c "import json,sys; print(json.dumps({'target': sys.argv[1], 'prompt': sys.argv[2], 'detected_at': sys.argv[3]}))" "$sem_target" "$sem_prompt" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
      _write_pending_json "${pending_dir}/pending-reviews.json" "$entry_json"
      issues_found=$((issues_found + 1))
    done < "${result_dir}/semantic_flagged"
  fi

  # Cleanup temp dir
  rm -rf "$result_dir"

  # Step 9: Notify
  if [[ "$issues_found" -gt 0 ]]; then
    _watch_notify "${issues_found} sensitive file(s) may be stale after merge to main" "$headless"
  fi

  # Step 10: Auto-reinstall check
  _auto_reinstall_check "$project_dir" "$origin_sha" "$headless" "$dry_run"

  # Step 11: Fast-forward local main (only if on main and clean)
  local current_branch
  current_branch="$(git -C "$project_dir" branch --show-current 2>/dev/null || echo "")"
  if [[ "$current_branch" == "main" ]]; then
    local status_output
    status_output="$(git -C "$project_dir" status --porcelain 2>/dev/null || echo "dirty")"
    if [[ -z "$status_output" ]]; then
      git -C "$project_dir" merge --ff-only origin/main >/dev/null 2>&1 || true
    fi
  fi

  # Step 12: Update tracking SHA
  mkdir -p "$(dirname "$sha_file")"
  echo "$origin_sha" > "$sha_file"
}

# ── Setup / Remove ───────────────────────────────────────────────────────────

# _watch_setup [project_dir] — install cron job + post-merge hook
_watch_setup() {
  local project_dir="${1:-$(pwd)}"
  project_dir="$(cd "$project_dir" && pwd)"  # resolve to absolute

  local devflow_bin
  devflow_bin="$(command -v devflow 2>/dev/null || echo "${DEVFLOW_ROOT:-$(devflow_root)}/bin/devflow")"

  section "Sensitive File Watchdog Setup"
  echo ""
  info "This will:"
  echo "  - Add a cron job (every 5 min) to fetch origin and check for stale files"
  echo "  - Install a git post-merge hook for immediate checks when you pull"
  echo "  - Only affects this project ($project_dir)"
  echo "  - To remove: devflow watch remove"
  echo ""
  printf "Proceed? [y/N] "
  read -r confirm
  if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
    info "Aborted."
    return 0
  fi

  # 1. Install cron job
  local cron_entry="*/5 * * * * cd ${project_dir} && ${devflow_bin} watch --headless --project ${project_dir} 2>&1 >> \${HOME}/.devflow/watch.log"
  local cron_marker="# devflow-watch:${project_dir}"

  if crontab -l 2>/dev/null | grep -qF "devflow-watch:${project_dir}"; then
    skip "Cron entry already exists"
  else
    (crontab -l 2>/dev/null || true; echo "${cron_marker}"; echo "${cron_entry}") | crontab -
    ok "Cron job installed (every 5 minutes)"
  fi

  # 2. Install post-merge hook
  local hook_file="${project_dir}/.git/hooks/post-merge"
  local marker_start="# --- devflow-watch start ---"
  local marker_end="# --- devflow-watch end ---"

  if [[ -f "$hook_file" ]] && grep -qF "$marker_start" "$hook_file"; then
    skip "Post-merge hook already installed"
  else
    mkdir -p "$(dirname "$hook_file")"
    if [[ ! -f "$hook_file" ]]; then
      echo "#!/usr/bin/env bash" > "$hook_file"
    fi
    cat >> "$hook_file" <<HOOK

${marker_start}
${devflow_bin} watch --immediate --project ${project_dir} 2>/dev/null || true
${marker_end}
HOOK
    chmod +x "$hook_file"
    ok "Post-merge hook installed"
  fi

  # 3. Store marker
  mkdir -p "${project_dir}/.devflow"
  echo "setup_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "${project_dir}/.devflow/.dev-setup"
  echo "project=${project_dir}" >> "${project_dir}/.devflow/.dev-setup"

  # 3b. Ask about auto-reinstall (only for devflow repo)
  if [[ -f "${project_dir}/lib/watch.sh" ]] && [[ -f "${project_dir}/bin/devflow" ]]; then
    echo ""
    info "This appears to be the devflow source repo."
    printf "Enable auto-reinstall? (Updates your local devflow when main gets new commits) [y/N] "
    read -r auto_reinstall_confirm
    if [[ "$auto_reinstall_confirm" == "y" ]] || [[ "$auto_reinstall_confirm" == "Y" ]]; then
      echo "auto_reinstall=true" >> "${project_dir}/.devflow/.dev-setup"
      ok "Auto-reinstall enabled"
    else
      skip "Auto-reinstall skipped"
    fi
  fi

  # 4. Create default config if missing
  if [[ ! -f "${project_dir}/.devflow/sensitive-files.conf" ]]; then
    info "No sensitive-files.conf found. Creating default config..."
    cat > "${project_dir}/.devflow/sensitive-files.conf" <<'CONF'
# .devflow/sensitive-files.conf
# Format: CHECK_TYPE | TARGET | SOURCES (comma-separated globs) | CHECK_CMD_OR_PROMPT
# CHECK_TYPE: mechanical (auto-fixable) | semantic (needs AI/human review)
# Makefile VERSION is the authoritative version source.

# Version-bearing targets
mechanical | lib/utils.sh | Makefile | devflow check-version
mechanical | devflow-plugin/.claude-plugin/plugin.json | Makefile | devflow check-version
mechanical | devflow-plugin/.claude-plugin/marketplace.json | Makefile | devflow check-version
mechanical | devflow-plugin/commands/*.md | Makefile | devflow check-version

# Docs derived from code
semantic | CLAUDE.md | lib/*.sh,lib/hooks/*.sh,devflow-plugin/commands/*.md,Makefile | Compare the Project Structure section in CLAUDE.md against the actual file tree. Flag discrepancies.
semantic | README.md | install.sh,Formula/devflow.rb,Makefile | Verify README install instructions match the actual install.sh and Makefile targets.

# Templates + generated
mechanical | Formula/devflow.rb | Makefile | devflow check-formula
CONF
    ok "Default sensitive-files.conf created"
  fi

  echo ""
  log "Watchdog setup complete."
}

# _watch_remove [project_dir] — remove cron job + post-merge hook
_watch_remove() {
  local project_dir="${1:-$(pwd)}"
  project_dir="$(cd "$project_dir" && pwd)"

  section "Removing Sensitive File Watchdog"

  # 1. Remove cron entry
  if crontab -l 2>/dev/null | grep -qF "devflow-watch:${project_dir}"; then
    # Remove both marker and command lines in a single pass
    crontab -l 2>/dev/null \
      | grep -vF "devflow-watch:${project_dir}" \
      | grep -vF "${project_dir}" \
      | crontab -
    ok "Cron entry removed"
  else
    skip "No cron entry found for this project"
  fi

  # 2. Remove post-merge hook section
  local hook_file="${project_dir}/.git/hooks/post-merge"
  local marker_start="# --- devflow-watch start ---"
  local marker_end="# --- devflow-watch end ---"

  if [[ -f "$hook_file" ]] && grep -qF "$marker_start" "$hook_file"; then
    # Remove between markers (inclusive)
    sed -i'' -e "/${marker_start}/,/${marker_end}/d" "$hook_file"
    # Remove empty trailing newlines
    sed -i'' -e :a -e '/^\n*$/{$d;N;ba;}' "$hook_file"
    ok "Post-merge hook section removed"
    # If hook file is now just the shebang, remove it
    local line_count
    line_count="$(wc -l < "$hook_file" | tr -d ' ')"
    if [[ "$line_count" -le 1 ]]; then
      rm -f "$hook_file"
      detail "Empty post-merge hook file removed"
    fi
  else
    skip "No devflow-watch section in post-merge hook"
  fi

  # 3. Remove marker
  rm -f "${project_dir}/.devflow/.dev-setup"
  ok "Setup marker removed"

  echo ""
  log "Watchdog removed for ${project_dir}."
}
