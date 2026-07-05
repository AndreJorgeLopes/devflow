#!/usr/bin/env bash
# devflow trace-review - per-skill week-over-week Langfuse regression report.
#
# READ-ONLY analysis of the local Langfuse trace store. The heavy aggregation lives
# in lib/trace-review.py (deterministic); this wrapper sources credentials, checks
# Langfuse is reachable, runs the engine, and provides a provider-agnostic scheduler.
#
# Architectural truth: Claude Code skills are markdown loaded from disk, NOT fetched
# from Langfuse. This command only READS traces; it never makes any skill's behavior
# depend on Langfuse. It is the READ half of the loop (the OTel collector is the WRITE half).

# ── credential loading (graceful) ──
_trace_review_load_creds() {
  if [[ -z "${LANGFUSE_PUBLIC_KEY:-}" || -z "${LANGFUSE_SECRET_KEY:-}" ]]; then
    local secrets="${HOME}/.config/zsh/secrets"
    if [[ -f "$secrets" ]]; then
      set -a; # shellcheck disable=SC1090
      source "$secrets" 2>/dev/null || true
      set +a
    fi
  fi
  : "${LANGFUSE_HOST:=http://localhost:3100}"
  export LANGFUSE_HOST
}

_trace_review_engine() {
  echo "${DEVFLOW_ROOT:-$(devflow_root)}/lib/trace-review.py"
}

# ── reachability ──
_trace_review_reachable() {
  curl -fsS -o /dev/null --connect-timeout 4 "${LANGFUSE_HOST}/api/public/health" 2>/dev/null
}

# devflow_trace_review [run|schedule|unschedule] [flags]
#   run (default)   Produce the report. Flags: --json | --output FILE | --window N | --since-now ISO
#   schedule        Install a weekly run (provider-agnostic). Flags: --backend cron|claude --cron "<expr>"
#   unschedule      Remove the installed cron entry for this project
devflow_trace_review() {
  local sub="run"
  case "${1:-}" in
    run|schedule|unschedule) sub="$1"; shift ;;
    ""|-*)                   sub="run" ;;   # no arg, or a flag → default to run
    *)  die "Unknown trace-review subcommand: $1 (use run|schedule|unschedule)" ;;
  esac

  case "$sub" in
    run)        _trace_review_run "$@" ;;
    schedule)   _trace_review_schedule "$@" ;;
    unschedule) _trace_review_unschedule "$@" ;;
    *)          die "Unknown trace-review subcommand: $sub" ;;
  esac
}

_trace_review_run() {
  local fmt="md" output="" window="" now=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)      fmt="json"; shift ;;
      --md)        fmt="md"; shift ;;
      --output)    output="$2"; shift 2 ;;
      --window)    window="$2"; shift 2 ;;
      --since-now) now="$2"; shift 2 ;;   # ISO timestamp; pins "now" for reproducible runs
      --project)   shift; [[ $# -gt 0 ]] && shift ;;  # accepted for cron-entry symmetry; value ignored (engine is project-agnostic). Guarded so a trailing --project with no value does not abort under set -euo pipefail.
      *)           shift ;;
    esac
  done

  _trace_review_load_creds
  if [[ -z "${LANGFUSE_PUBLIC_KEY:-}" || -z "${LANGFUSE_SECRET_KEY:-}" ]]; then
    die "LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY not set. Add them to ~/.config/zsh/secrets or export them."
  fi
  if ! _trace_review_reachable; then
    die "Langfuse not reachable at ${LANGFUSE_HOST}. Start it with: devflow up   (then retry)."
  fi

  [[ -n "$window" ]] && export TRACE_REVIEW_WINDOW_DAYS="$window"
  [[ -n "$now" ]] && export TRACE_REVIEW_NOW="$now"

  local engine; engine="$(_trace_review_engine)"
  [[ -f "$engine" ]] || die "engine not found: $engine"

  if [[ -n "$output" ]]; then
    python3 "$engine" --format "$fmt" > "$output" || die "trace-review engine failed"
    ok "Report written: $output"
  else
    python3 "$engine" --format "$fmt"
  fi
}

# ── scheduler (provider-agnostic; two seams: backend + agent-invoke command) ──
# Mirrors lib/watch.sh _watch_setup: idempotent crontab marker per project.
_trace_review_schedule() {
  local backend="cron" cron_expr="0 9 * * 1"   # default: Monday 09:00 local
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --backend) backend="$2"; shift 2 ;;
      --cron)    cron_expr="$2"; shift 2 ;;
      *)         shift ;;
    esac
  done

  local project_dir; project_dir="$(pwd)"
  local devflow_bin
  devflow_bin="$(command -v devflow 2>/dev/null || echo "${DEVFLOW_ROOT:-$(devflow_root)}/bin/devflow")"

  case "$backend" in
    cron)
      # OS-level cron - the ONLY backend portable across Claude Code AND OpenCode today.
      local provider; provider="$(detect_agent_provider)"
      local report_dir="${HOME}/.devflow/trace-review"
      mkdir -p "$report_dir"
      local out_file="${report_dir}/\$(date -u +%Y-%m-%d).md"
      local cron_marker="# devflow-trace-review:${project_dir}"
      local cron_entry="${cron_expr} cd ${project_dir} && ${devflow_bin} trace-review run --output ${out_file} >> ${report_dir}/trace-review.log 2>&1"

      if crontab -l 2>/dev/null | grep -qF "devflow-trace-review:${project_dir}"; then
        skip "Cron entry already exists for this project"
      else
        (crontab -l 2>/dev/null || true; echo "${cron_marker}"; echo "${cron_entry}") | crontab -
        ok "Weekly cron installed (${cron_expr}) - agent provider: ${provider}"
        info "Reports land in ${report_dir}/. Note: the machine must be awake at fire time."
      fi
      ;;
    claude)
      # Claude Code cloud Routine - runs even when the machine is off, but Claude-only.
      # The CLI cannot create a cloud routine (that needs the scheduled-tasks MCP); emit
      # the recommended routine spec for the SKILL to register interactively.
      info "Claude Code routine spec (register via the /devflow:trace-review skill, which drives the scheduled-tasks MCP):"
      cat <<SPEC
  name:            devflow-trace-review-weekly
  cronExpression:  ${cron_expr}
  prompt:          /devflow:trace-review run
  note:            Cloud routine runs when the machine is off, but is Claude-Code-specific
                   (OpenCode has no native scheduler - use --backend cron there).
SPEC
      ;;
    *)
      die "Unknown scheduler backend: ${backend} (supported: cron, claude). To add a provider, see lib/utils.sh detect_agent_provider + this case."
      ;;
  esac
}

_trace_review_unschedule() {
  local project_dir; project_dir="$(pwd)"
  if crontab -l 2>/dev/null | grep -qF "devflow-trace-review:${project_dir}"; then
    crontab -l 2>/dev/null | grep -vF "devflow-trace-review:${project_dir}" \
      | grep -vF "${project_dir} && $(command -v devflow 2>/dev/null || echo devflow) trace-review" \
      | crontab -
    ok "Removed weekly cron entry for ${project_dir}"
  else
    skip "No cron entry found for this project"
  fi
}
