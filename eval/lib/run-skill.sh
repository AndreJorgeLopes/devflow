#!/usr/bin/env bash
# promptfoo `exec:` provider wrapper — runs a devflow skill headlessly and
# emits its raw stdout as the output-under-test.
#
# promptfoo calls this as:  run-skill.sh "<prompt>" "<json-context>"
#   $1 = the rendered prompt (the skill invocation, e.g. "/devflow:resolve-repo ...")
#   $2 = JSON context (ignored)
#
# GATE FIDELITY: we test the WORKING-TREE skill, not whatever devflow plugin is
# installed globally. To do that we stage the local skill into a throwaway project
# dir (.claude/commands/<name>.md + .claude/skills/<name>/) and invoke it there as a
# PROJECT command `/<name>` (no `devflow:` prefix, so it can't collide with an
# installed `/devflow:<name>`). Editing skills/<name>/SKILL.md + `make skills-sync`
# is therefore enough to gate a pending change — no reinstall/link needed.
# (Feeding the body via --append-system-prompt was tried and is unreliable: it
# conflicts with any installed command and the model improvises.)
#
# Env knobs:
#   SKILL_EVAL_MODEL   model id (default: sonnet — haiku is too weak to adhere to a
#                      pinned output shape, so it flaps these asserts; verified. Override
#                      to haiku only for a skill whose asserts don't depend on strict format.)
#   SKILL_EVAL_TIMEOUT seconds before kill (default: 300)
#
# IMPORTANT: clears CLAUDECODE so a nested `claude` can launch from inside a
# Claude Code session (claude-agent-sdk-python#573). Without this the child refuses.
set -euo pipefail

PROMPT="${1:-}"
MODEL="${SKILL_EVAL_MODEL:-claude-sonnet-5}"
TIMEOUT="${SKILL_EVAL_TIMEOUT:-300}"

if [[ -z "$PROMPT" ]]; then
  echo "run-skill.sh: empty prompt" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Parse "/devflow:<name> <args...>" (or "/<name> <args...>") into name + trailing args.
inv="${PROMPT#/}"          # devflow:resolve-repo <args>
inv="${inv#devflow:}"      # resolve-repo <args>
name="${inv%% *}"          # resolve-repo
args=""
[[ "$inv" == *" "* ]] && args="${inv#* }"   # everything after the command name

src_cmd="${ROOT}/devflow-plugin/commands/${name}.md"
if [[ ! -f "$src_cmd" ]]; then
  echo "run-skill.sh: no local command for '${name}' at ${src_cmd} (run 'make skills-sync'?)" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/.claude/commands" "$work/.claude/skills"
cp "$src_cmd" "$work/.claude/commands/${name}.md"
if [[ -d "${ROOT}/skills/${name}" ]]; then
  cp -R "${ROOT}/skills/${name}" "$work/.claude/skills/${name}"
  # Drop dev-only files that must not ship / are irrelevant to execution.
  rm -f "$work/.claude/skills/${name}/determinism.promptfooconfig.yaml" \
        "$work/.claude/skills/${name}/eval-run.sh"
fi

# Invoke the LOCAL skill as a project command from the staged dir.
cd "$work"
env CLAUDECODE="" timeout "$TIMEOUT" \
  claude --model "$MODEL" --print "/${name}${args:+ $args}"
