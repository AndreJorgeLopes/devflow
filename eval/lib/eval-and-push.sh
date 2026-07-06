#!/usr/bin/env bash
# eval-and-push.sh — run a skill's quality evaluators and push BOTH scores into Langfuse
# so `devflow trace-review`'s score column fills automatically. This is the "pump" that
# feeds the score pipe: call it from wherever a skill is reviewed (create-skill /
# optimize-skill / a pre-PR gate) so the column populates without a manual push.
#
# Pushes both sources the trace-review score column understands:
#   1. tessl review score (.review.reviewScore, 0..100) via tessl-push.sh — the signal
#      that actually VARIES with quality.
#   2. promptfoo pass-rate via langfuse-push.sh — only meaningful when the skill's config
#      has a quality/judge assert; shape-only asserts sit at 1.0. Run when a
#      determinism.promptfooconfig.yaml exists next to the skill.
#
# Both are best-effort and independent: a missing tessl login or promptfoo config skips
# that half with a notice, never aborts the other.
#
# Usage:
#   bash eval/lib/eval-and-push.sh <skill-name> [skill-dir] [version-label]
#     <skill-name>   e.g. trace-review  (the name trace-review attributes by)
#     [skill-dir]    default skills/<skill-name>
#     [version-label] default: short git sha, else "head"
#
# Env: TESSL_WORKSPACE (default andrejorgelopes), LANGFUSE_* (from ~/.config/zsh/secrets).
set -euo pipefail

SKILL="${1:?usage: eval-and-push.sh <skill-name> [skill-dir] [version-label]}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SKILL_DIR="${2:-$ROOT/skills/$SKILL}"
VERSION="${3:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo head)}"
WORKSPACE="${TESSL_WORKSPACE:-andrejorgelopes}"

# credentials (graceful). Contain the source under set +e: a secrets file ending in a
# non-zero-returning line would otherwise abort this script under set -e (|| true on
# `source` alone is insufficient on bash 3.2 - set -e fires inside the sourced file).
if [[ -z "${LANGFUSE_PUBLIC_KEY:-}" || -z "${LANGFUSE_SECRET_KEY:-}" ]]; then
  if [[ -f "$HOME/.config/zsh/secrets" ]]; then
    set -a; set +e
    # shellcheck disable=SC1091
    source "$HOME/.config/zsh/secrets" 2>/dev/null
    set -e; set +a
  fi
fi
export LANGFUSE_HOST="${LANGFUSE_HOST:-http://localhost:3100}"

if [[ ! -d "$SKILL_DIR" ]]; then
  echo "eval-and-push: skill dir not found: $SKILL_DIR" >&2; exit 2
fi

pushed_any=0

# ── 1. tessl review -> tessl-push ──
if command -v tessl >/dev/null 2>&1; then
  tmp="$(mktemp)"
  if tessl review run --workspace "$WORKSPACE" --json "$SKILL_DIR" >"$tmp" 2>/dev/null; then
    score="$(python3 -c "import json,sys; d=json.load(open('$tmp')); print(d.get('review',{}).get('reviewScore',''))" 2>/dev/null || echo "")"
    if [[ -n "$score" ]]; then
      bash "$HERE/tessl-push.sh" "$SKILL" "$score" "$VERSION" && pushed_any=1
    else
      echo "eval-and-push: tessl review produced no .review.reviewScore — skipping tessl push" >&2
    fi
  else
    echo "eval-and-push: tessl review failed (login/workspace?) — skipping tessl push" >&2
  fi
  rm -f "$tmp"
else
  echo "eval-and-push: tessl not on PATH — skipping tessl push" >&2
fi

# ── 2. promptfoo -> langfuse-push (only if a config exists for this skill) ──
cfg="$SKILL_DIR/determinism.promptfooconfig.yaml"
if [[ -f "$cfg" ]]; then
  # mktemp returns a real file; the promptfoo output needs a .json name. Track BOTH the
  # base file mktemp created and the .json we actually write, so cleanup removes both
  # (appending .json to $(mktemp) would orphan the base file).
  results_base="$(mktemp)"; results="${results_base}.json"
  if (cd "$SKILL_DIR" && npx -y promptfoo@latest eval -c "$cfg" --output "$results" >/dev/null 2>&1); then
    bash "$HERE/langfuse-push.sh" "$results" "$SKILL" "$VERSION" && pushed_any=1
  else
    echo "eval-and-push: promptfoo eval failed — skipping promptfoo push" >&2
  fi
  rm -f "$results" "$results_base"
else
  echo "eval-and-push: no determinism.promptfooconfig.yaml for $SKILL — skipping promptfoo push" >&2
fi

if [[ "$pushed_any" -eq 1 ]]; then
  echo "eval-and-push: done (skill=$SKILL version=$VERSION). trace-review score column will reflect it."
else
  echo "eval-and-push: nothing pushed for $SKILL (no working evaluator)." >&2
  exit 1
fi
