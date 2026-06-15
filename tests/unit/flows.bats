#!/usr/bin/env bats
# tests/unit/flows.bats — flow generator + drift guard + diagrams bundle.
# Phase A: A1 (generate tree, per-flow plugin.json name/version, byte-identity), A2 (flows-check drift).
# Phase D: D2 (diagrams flow bundles standalone render launcher + export script).

load '../helpers/common'
load '../helpers/assertions'

setup() { REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"; }

@test "build-flows generates each flow as a self-contained mini-plugin" {
  run bash "${REPO}/scripts/build-flows.sh"
  assert_success
  for fl in review diagrams jira; do
    assert [ -f "${REPO}/devflow-plugin/flows/${fl}/.claude-plugin/plugin.json" ]
  done
  assert [ -f "${REPO}/devflow-plugin/flows/review/skills/write-spike/SKILL.md" ]
  assert [ -f "${REPO}/devflow-plugin/flows/review/skills/write-spike/requirements.json" ]
  assert [ -f "${REPO}/devflow-plugin/flows/diagrams/skills/render-diagram/SKILL.md" ]
}

@test "flow plugin.json name is devflow-<flow> and version matches the full plugin" {
  bash "${REPO}/scripts/build-flows.sh" >/dev/null
  local v; v="$(jq -r .version "${REPO}/devflow-plugin/.claude-plugin/plugin.json")"
  run jq -r .name "${REPO}/devflow-plugin/flows/review/.claude-plugin/plugin.json"
  assert_output "devflow-review"
  run jq -r .version "${REPO}/devflow-plugin/flows/review/.claude-plugin/plugin.json"
  assert_output "$v"
}

@test "flow copies are byte-identical to canonical skill SKILL.md" {
  bash "${REPO}/scripts/build-flows.sh" >/dev/null
  run diff "${REPO}/devflow-plugin/skills/render-diagram/SKILL.md" "${REPO}/devflow-plugin/flows/diagrams/skills/render-diagram/SKILL.md"
  assert_success
}

@test "flows-check fails when a canonical skill changed but flows were not regenerated" {
  # ${REPO} is a git WORKTREE: ${REPO}/.git is a gitlink FILE pointing at the real
  # branch's admin dir. A plain `cp -R` would share that admin dir, so committing in
  # the copy could advance the real hardcore-raman branch. Re-init the copy as a
  # standalone repo so the drift snapshot is fully isolated (also required for the
  # GREEN path: drift detection needs a committed standalone flows/ baseline).
  local work="${BATS_TEST_TMPDIR}/repo"; cp -R "${REPO}" "$work"
  rm -rf "$work/.git"
  git -C "$work" init -q
  git -C "$work" -c user.email=t -c user.name=t add -A
  git -C "$work" -c user.email=t -c user.name=t commit -q -m snapshot
  # Tamper the CANONICAL source (uncommitted). flows-check's first action is build-flows.sh,
  # which regenerates the flow copy FROM the tampered canonical -> working-tree flow now
  # differs from the committed flow -> `git diff -- flows` is dirty -> flows-check exits 1.
  # (Tampering the generated copy instead would be wiped by build-flows' rm -rf before the diff.)
  printf '\n<!-- drift -->\n' >> "$work/devflow-plugin/skills/render-diagram/SKILL.md"
  run make -C "$work" flows-check
  assert_failure
  # RED-correct: at RED `make` errors with "No rule to make target 'flows-check'" (assert_failure
  # passes vacuously), so also require the actual drift message — absent until A2 lands.
  assert_output --partial "flows out of date"
}

@test "diagrams flow bundles a standalone render launcher + export script" {
  bash "${REPO}/scripts/build-flows.sh" >/dev/null
  assert [ -x "${REPO}/devflow-plugin/flows/diagrams/skills/render-diagram/render.sh" ]
  assert [ -f "${REPO}/devflow-plugin/flows/diagrams/skills/render-diagram/excalidraw-export.cjs" ]
}
