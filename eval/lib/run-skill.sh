#!/usr/bin/env bash
# promptfoo `exec:` provider wrapper — runs a devflow skill headlessly and
# emits its raw stdout as the output-under-test.
#
# promptfoo calls this as:  run-skill.sh "<prompt>" "<json-context>"
#   $1 = the rendered prompt (the skill invocation, e.g. "/devflow:resolve-repo ...")
#   $2 = JSON context (ignored)
#
# Env knobs:
#   SKILL_EVAL_MODEL   model id (default: haiku — cheap/fast for asserts)
#   SKILL_EVAL_TIMEOUT seconds before kill (default: 300)
#
# IMPORTANT: clears CLAUDECODE so a nested `claude` can launch from inside a
# Claude Code session (claude-agent-sdk-python#573). Without this, the child
# refuses to start.
set -euo pipefail

PROMPT="${1:-}"
MODEL="${SKILL_EVAL_MODEL:-claude-haiku-4-5-20251001}"
TIMEOUT="${SKILL_EVAL_TIMEOUT:-300}"

if [[ -z "$PROMPT" ]]; then
  echo "run-skill.sh: empty prompt" >&2
  exit 2
fi

exec env CLAUDECODE="" timeout "$TIMEOUT" \
  claude --model "$MODEL" --print "$PROMPT"
