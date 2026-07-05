#!/usr/bin/env bash
# devflow/lib/langfuse-mirror.sh — mirror skills/<name>/SKILL.md into Langfuse prompt-management.
#
# Component (b) of the trace-improvement loop (docs/plans/2026-06-30-langfuse-trace-improvement-loop.md).
# Pushes each authored SKILL.md as a new version of a Langfuse text prompt named `skill/<name>`
# (label `production`), giving versioned history + diff in the Langfuse UI and a stable handle to
# link traces to a skill version.
#
# LOAD-BEARING CAVEAT (spike §2): this is a MIRROR ONLY. Claude Code loads skills from disk; it
# does NOT fetch them from Langfuse at runtime. Editing the Langfuse prompt does NOT change skill
# behavior. The git SKILL.md is the source of truth; this is a read-only history surface.
#
# Idempotent: a skill whose SKILL.md is byte-identical to its latest Langfuse version is SKIPPED,
# so re-running without content changes creates no new versions (no version spam).
#
# Auth: LANGFUSE_HOST (default http://localhost:3100) + LANGFUSE_PUBLIC_KEY/LANGFUSE_SECRET_KEY
# (sourced from ~/.config/zsh/secrets if present). Read-only against git; only writes to Langfuse.

set -euo pipefail

langfuse_mirror() {
  local only="" dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)    only="$2"; shift 2 ;;
      --dry-run) dry_run=true; shift ;;
      *) echo "Usage: devflow skills mirror [--name <skill>] [--dry-run]" >&2; return 2 ;;
    esac
  done

  [[ -f "$HOME/.config/zsh/secrets" ]] && { set -a; . "$HOME/.config/zsh/secrets" 2>/dev/null || true; set +a; }
  local host="${LANGFUSE_HOST:-http://localhost:3100}"
  local pk="${LANGFUSE_PUBLIC_KEY:-}" sk="${LANGFUSE_SECRET_KEY:-}"
  if [[ -z "$pk" || -z "$sk" ]]; then
    echo "langfuse-mirror: LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY not set (see ~/.config/zsh/secrets)" >&2
    return 1
  fi
  command -v jq >/dev/null 2>&1 || { echo "langfuse-mirror: jq is required" >&2; return 1; }

  local root; root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local src_dir="${root}/skills"
  local sha; sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  local branch; branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

  # urlencode via jq (@uri) — handles the '/' in skill/<name>.
  _enc() { printf '%s' "$1" | jq -sRr @uri; }

  local pushed=0 skipped=0 total=0
  local d name skill_md prompt_name enc current content
  for d in "$src_dir"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    [[ -n "$only" && "$only" != "$name" ]] && continue
    skill_md="${d}SKILL.md"
    [[ -f "$skill_md" ]] || continue
    total=$((total+1))
    prompt_name="skill/${name}"
    enc="$(_enc "$prompt_name")"
    content="$(cat "$skill_md")"

    # Current latest version's content (empty if the prompt does not exist yet).
    current="$(curl -s -u "${pk}:${sk}" "${host}/api/public/v2/prompts/${enc}" 2>/dev/null \
      | jq -r 'if type=="object" and has("prompt") then .prompt else "" end' 2>/dev/null || true)"

    if [[ -n "$current" && "$current" == "$content" ]]; then
      skipped=$((skipped+1))
      echo "  = ${prompt_name} (unchanged)"
      continue
    fi

    if $dry_run; then
      pushed=$((pushed+1))
      echo "  ~ ${prompt_name} (would push new version)"
      continue
    fi

    local body http
    body="$(jq -n --arg n "$prompt_name" --arg p "$content" \
      --arg msg "sync ${sha} (${branch})" \
      '{name:$n, type:"text", prompt:$p, labels:["production"], commitMessage:$msg}')"
    http="$(curl -s -o /dev/null -w '%{http_code}' -u "${pk}:${sk}" \
      -X POST "${host}/api/public/v2/prompts" -H "Content-Type: application/json" -d "$body" 2>/dev/null || echo 000)"
    if [[ "$http" == "200" || "$http" == "201" ]]; then
      pushed=$((pushed+1)); echo "  + ${prompt_name} (new version pushed)"
    else
      echo "  ! ${prompt_name} (push failed: HTTP ${http})" >&2
      return 1
    fi
  done

  local suffix=""; $dry_run && suffix=" (dry-run)"
  echo "langfuse-mirror: ${total} skill(s) — ${pushed} pushed, ${skipped} unchanged${suffix}"
}
