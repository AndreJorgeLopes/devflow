#!/usr/bin/env bats
# tests/integration/skills-convert.bats — orphan-preservation tests for
# `devflow skills convert`. Regression coverage for the 2026-05-11 bug
# where rm -rf "$output" silently wiped any hand-authored slash command
# in devflow-plugin/commands/ that wasn't in skills/registry.json.

setup() {
  load '../helpers/common'
  _common_setup
  TMP_PLUGIN="${BATS_TEST_TMPDIR}/plugin"
}

teardown() {
  _common_teardown
}

# ── Baseline: plain convert into a temp output dir ─────────────────

@test "skills convert writes all registry skills into a fresh output dir" {
  run "${DEVFLOW_ROOT}/bin/devflow" skills convert --output "$TMP_PLUGIN"
  assert_success
  assert [ -d "${TMP_PLUGIN}/commands" ]
  assert [ -d "${TMP_PLUGIN}/skills" ]
  assert [ -f "${TMP_PLUGIN}/.claude-plugin/plugin.json" ]
  # At least one known registry skill is materialized
  assert [ -f "${TMP_PLUGIN}/skills/recall-before-task/SKILL.md" ]
  assert [ -f "${TMP_PLUGIN}/commands/recall-before-task.md" ]
}

# ── The regression test the user actually asked for ────────────────

@test "skills convert preserves orphan command files by default" {
  # First populate the plugin dir from the registry
  run "${DEVFLOW_ROOT}/bin/devflow" skills convert --output "$TMP_PLUGIN"
  assert_success

  # Pre-seed an orphan slash command — a file not backed by any registry entry
  printf -- '---\ndescription: an orphan command\n---\n\nbody\n' \
    > "${TMP_PLUGIN}/commands/orphan-cmd.md"

  # Re-run convert. Under the old code this would silently rm -rf the file.
  run "${DEVFLOW_ROOT}/bin/devflow" skills convert --output "$TMP_PLUGIN"
  assert_success

  # The orphan must still be on disk
  assert [ -f "${TMP_PLUGIN}/commands/orphan-cmd.md" ]
  # And the output must surface the orphan to the user
  assert_output --partial "orphan-cmd.md"
  assert_output --partial "PRESERVED"
}

@test "skills convert preserves orphan skill directories by default" {
  run "${DEVFLOW_ROOT}/bin/devflow" skills convert --output "$TMP_PLUGIN"
  assert_success

  # Pre-seed an orphan skill folder (no entry in skills/registry.json)
  mkdir -p "${TMP_PLUGIN}/skills/orphan-skill"
  printf -- '---\nname: orphan-skill\ndescription: orphan\n---\n' \
    > "${TMP_PLUGIN}/skills/orphan-skill/SKILL.md"

  run "${DEVFLOW_ROOT}/bin/devflow" skills convert --output "$TMP_PLUGIN"
  assert_success

  assert [ -d "${TMP_PLUGIN}/skills/orphan-skill" ]
  assert [ -f "${TMP_PLUGIN}/skills/orphan-skill/SKILL.md" ]
  assert_output --partial "orphan-skill"
}

# ── Opt-in destructive mode ────────────────────────────────────────

@test "skills convert --prune removes orphan command files" {
  run "${DEVFLOW_ROOT}/bin/devflow" skills convert --output "$TMP_PLUGIN"
  assert_success

  printf -- '---\n' > "${TMP_PLUGIN}/commands/orphan-cmd.md"

  run "${DEVFLOW_ROOT}/bin/devflow" skills convert --output "$TMP_PLUGIN" --prune
  assert_success

  assert [ ! -f "${TMP_PLUGIN}/commands/orphan-cmd.md" ]
  assert_output --partial "removed"
}

@test "skills convert --prune removes orphan skill directories" {
  run "${DEVFLOW_ROOT}/bin/devflow" skills convert --output "$TMP_PLUGIN"
  assert_success

  mkdir -p "${TMP_PLUGIN}/skills/orphan-skill"
  : > "${TMP_PLUGIN}/skills/orphan-skill/SKILL.md"

  run "${DEVFLOW_ROOT}/bin/devflow" skills convert --output "$TMP_PLUGIN" --prune
  assert_success

  assert [ ! -d "${TMP_PLUGIN}/skills/orphan-skill" ]
  assert_output --partial "removed"
}

# ── No-orphan case: stay quiet ─────────────────────────────────────

@test "skills convert emits no orphan warning when none exist" {
  run "${DEVFLOW_ROOT}/bin/devflow" skills convert --output "$TMP_PLUGIN"
  assert_success
  refute_output --partial "PRESERVED"
  refute_output --partial "orphan"
}
