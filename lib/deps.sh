#!/usr/bin/env bash
# devflow/lib/deps.sh — `devflow deps check <skill>` : report required/optional dep status.
# Deterministic accelerator for each skill's prompt-driven ## Preflight block. Reads the
# skill's requirements.json, runs each dep's `check`, prints a table. Exits non-zero (naming
# the dep) when a REQUIRED dep is missing; OPTIONAL deps only warn. Never required by a skill.
# Sourced by bin/devflow.

# _deps_resolve_file <skill> | --file <path>  → echoes path to a requirements.json
_deps_resolve_file() {
  if [[ "${1:-}" == "--file" ]]; then echo "${2:-}"; return 0; fi
  local skill="${1:?usage: devflow deps check <skill>|--file <path>}"
  local root; root="$(devflow_root)"
  local c
  for c in "${root}/devflow-plugin/skills/${skill}/requirements.json" "${root}/skills/${skill}/requirements.json"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

# _deps_check_one <check-string> → 0 present, 1 missing.
# A `check` is either a shell command (exit 0 ⇒ present) or a named probe for a
# non-command dep. Only `hindsight` is a named probe today (the design enumerates
# the supported probes); anything else is eval'd as a shell command.
_deps_check_one() {
  local check="$1"
  case "$check" in
    hindsight) [[ -n "${HINDSIGHT_URL:-}" ]] || command -v uvx >/dev/null 2>&1 ;;  # best-effort reachability
    *)         eval "$check" >/dev/null 2>&1 ;;
  esac
}

# devflow_deps check <skill>|--file <path>
devflow_deps() {
  local sub="${1:-}"; shift || true
  [[ "$sub" == "check" ]] || die "Usage: devflow deps check <skill>"
  local file; file="$(_deps_resolve_file "$@")" || die "No requirements.json for: ${1:-<skill>}"
  has_cmd jq || die "jq required for deps check"
  local skill; skill="$(jq -r '.skill // "?"' "$file")"
  section "deps: ${skill}"

  local missing_required=0 n chk why inst
  while IFS=$'\t' read -r n chk why inst; do
    if _deps_check_one "$chk"; then
      ok "required ${n}"
    else
      status_fail "required ${n} — ${why} (install: ${inst})"
      missing_required=1
    fi
  done < <(jq -r '.required[]? | [.name, .check, .why, (.install // "")] | @tsv' "$file")

  while IFS=$'\t' read -r n chk why inst; do
    if _deps_check_one "$chk"; then
      ok "optional ${n}"
    else
      warn "optional ${n} missing — ${why}"
    fi
  done < <(jq -r '.optional[]? | [.name, .check, .why, (.install // "")] | @tsv' "$file")

  [[ "$missing_required" -eq 0 ]] || return 1
  return 0
}
