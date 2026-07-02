#!/usr/bin/env bash
# promptfoo `exec:` provider for trace-review determinism asserts.
# Runs the DETERMINISTIC engine directly (not a nested LLM). This is a SHAPE smoke test:
# it runs against whatever traces exist "now", so the asserts pin the output STRUCTURE
# (valid JSON / table header / severity glyph / no code fence), NOT specific data values.
# Data-reproducible aggregation is covered by tests/unit/trace-review.bats (synthetic
# fixtures + TRACE_REVIEW_NOW). promptfoo passes the flags as $1 (e.g. "run" or "run --json").
# Requires Langfuse reachable (like /devflow:review needs a working-tree diff).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1090
[[ -f "$HOME/.config/zsh/secrets" ]] && { set -a; source "$HOME/.config/zsh/secrets" 2>/dev/null || true; set +a; }
# shellcheck disable=SC2086
exec "$ROOT/bin/devflow" trace-review ${1:-run}
