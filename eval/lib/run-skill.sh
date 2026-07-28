#!/usr/bin/env bash
# promptfoo `exec:` provider wrapper — runs a devflow skill headlessly and
# emits its raw stdout as the output-under-test.
#
# promptfoo calls this as:  run-skill.sh "<prompt>" "<json-context>"
#   $1 = the rendered prompt (the skill invocation, e.g. "/devflow:resolve-repo ...")
#   $2 = JSON context (ignored)
#
# GATE FIDELITY: we test the WORKING-TREE skill, not whatever devflow plugin is
# installed globally. We stage the local skill as a PROJECT command `/<name>` (no
# `devflow:` prefix, so it can't collide with an installed `/devflow:<name>`) and run
# claude there. Editing skills/<name>/SKILL.md + `make skills-sync` is enough to gate a
# pending change — no reinstall/link. (--append-system-prompt was tried and is unreliable:
# it conflicts with any installed command and the model improvises.)
#
# TWO MODES:
#  - Read-only skills (default): run FROM the repo root so context-dependent read-only skills
#    (review's diff, resolve-repo's dirs) see real context. Colliding .claude files are
#    backed up + restored.
#  - Side-effect skills (create-pr/finish-feature/new-feature/lock-tests/write-spike/verify-first):
#    the config's eval-run.sh sets DEVFLOW_EVAL=1; we then run inside a THROWAWAY git fixture
#    (no remote, no gh auth, deleted after) so the skill has context but any push / PR-create /
#    file write is contained. Such a skill is REFUSED unless DEVFLOW_EVAL=1 (footgun guard),
#    and it must itself honor DEVFLOW_EVAL (emit output, skip the irreversible action).
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

# Skills that perform irreversible side effects (push/open a PR, write files). They must ONLY
# run inside an isolated throwaway git fixture with DEVFLOW_EVAL=1 set — never against the real
# repo. Their eval-run.sh sets DEVFLOW_EVAL=1; the skill honors it (emit output, skip the side
# effect); and the fixture (no remote, no gh auth) is the belt-and-suspenders net if it does not.
SIDE_EFFECT_SKILLS=" create-pr finish-feature new-feature lock-tests write-spike verify-first "
_is_side_effect() { [[ "$SIDE_EFFECT_SKILLS" == *" $1 "* ]]; }

# Footgun guard: refuse to run a side-effect skill unless eval mode is on, so a stray
# `make determinism` (or a hand-run) can never push/write against the real repo.
if _is_side_effect "$name" && [[ "${DEVFLOW_EVAL:-}" != "1" ]]; then
  echo "run-skill.sh: '${name}' has side effects — refusing to run without DEVFLOW_EVAL=1 (its eval-run.sh must set it)." >&2
  exit 2
fi

# _stage_skill <dir> — install the working-tree skill into <dir> as a PROJECT command `/<name>`
# (+ its skill dir, minus dev-only files). Records what to restore in $BK.
BK="$(mktemp -d)"
_stage_skill() {
  local dir="$1"
  local cmd_dst="${dir}/.claude/commands/${name}.md"
  local skl_dst="${dir}/.claude/skills/${name}"
  mkdir -p "${dir}/.claude/commands" "${dir}/.claude/skills"
  [[ -e "$cmd_dst" ]] && cp -R "$cmd_dst" "${BK}/cmd"
  [[ -e "$skl_dst" ]] && cp -R "$skl_dst" "${BK}/skl"
  cp "$src_cmd" "$cmd_dst"
  if [[ -d "${ROOT}/skills/${name}" ]]; then
    rm -rf "$skl_dst"; cp -R "${ROOT}/skills/${name}" "$skl_dst"
    rm -f "${skl_dst}/determinism.promptfooconfig.yaml" "${skl_dst}/eval-run.sh"
  fi
  STAGE_CMD_DST="$cmd_dst"; STAGE_SKL_DST="$skl_dst"
}

if [[ "${DEVFLOW_EVAL:-}" == "1" ]]; then
  # Isolated mode: build a throwaway git fixture (feature branch 1 commit ahead of a local
  # main, sample plan/spec/doc, NO remote, NO gh auth) so a side-effect skill has real context
  # (a diff, commits, a plan) but any push / PR-create / file write is contained + discarded.
  FIX="$(mktemp -d)"
  trap 'rm -rf "$FIX" "$BK"' EXIT
  (
    cd "$FIX"
    git init -q -b main
    git config user.email eval@devflow.local; git config user.name devflow-eval
    printf '# Plan: EVAL-1 sample\n\n## Acceptance Criteria\n- AC1: the widget validates empty input\n- AC2: the widget rejects negative numbers\n\n## Claims to verify\n- The API returns 200 for a valid request\n- The parser handles UTF-8 input\n' > plan.md
    printf '# Spec: EVAL-1\n\nAdd input validation to the widget.\n' > spec.md
    printf '# Sample design doc\n\nThis runbook explains the deploy steps.\n\n## Step 1\nDo the thing.\n' > doc.md
    git add -A; git commit -q -m "chore: fixture base"
    git checkout -q -b feat/EVAL-1
    printf 'validated=true\n' > widget.conf
    git add -A; git commit -q -m "feat: add widget input validation (EVAL-1)"
  )
  _stage_skill "$FIX"
  cd "$FIX"
  env CLAUDECODE="" DEVFLOW_EVAL=1 timeout "$TIMEOUT" \
    claude --model "$MODEL" --print "/${name}${args:+ $args}"
else
  # Read-only mode: run FROM the repo root so context-dependent read-only skills (review's diff,
  # resolve-repo's dirs) see real context. Stage into the repo root; restore any colliding file
  # (e.g. the repo's own .claude/commands/plugin-sync.md) so the working tree is left as found.
  _restore() {
    [[ -e "${BK}/cmd" ]] && mv "${BK}/cmd" "$STAGE_CMD_DST" || rm -f "$STAGE_CMD_DST"
    [[ -e "${BK}/skl" ]] && { rm -rf "$STAGE_SKL_DST"; mv "${BK}/skl" "$STAGE_SKL_DST"; } || rm -rf "$STAGE_SKL_DST"
    rmdir "${ROOT}/.claude/commands" "${ROOT}/.claude/skills" "${ROOT}/.claude" 2>/dev/null || true
    rm -rf "$BK"
  }
  trap _restore EXIT
  _stage_skill "$ROOT"
  cd "$ROOT"
  env CLAUDECODE="" timeout "$TIMEOUT" \
    claude --model "$MODEL" --print "/${name}${args:+ $args}"
fi
