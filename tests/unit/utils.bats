#!/usr/bin/env bats
# tests/unit/utils.bats — Unit tests for lib/utils.sh

setup() {
  load '../helpers/common'
  _common_setup
  load '../helpers/mocks'
  load '../helpers/assertions'
  source_lib utils.sh
}

teardown() {
  _common_teardown
}

# ── has_cmd ───────────────────────────────────────────────────────

@test "has_cmd returns 0 for an available command (bash)" {
  run has_cmd bash
  assert_success
}

@test "has_cmd returns 1 for a nonexistent command" {
  run has_cmd nonexistent_xyz_12345
  assert_failure
}

# ── project_root ──────────────────────────────────────────────────

@test "project_root returns directory containing .git" {
  run project_root
  assert_success
  # In a regular checkout `.git` is a directory; in a worktree it's a file
  # pointing at the parent repo's gitdir. Accept either.
  assert [ -e "${output}/.git" ]
}

# ── devflow_root ──────────────────────────────────────────────────

@test "DEVFLOW_ROOT points to valid devflow installation" {
  assert [ -d "$DEVFLOW_ROOT" ]
  assert [ -x "$DEVFLOW_ROOT/bin/devflow" ]
  assert [ -f "$DEVFLOW_ROOT/lib/utils.sh" ]
}

# ── detect_vcs_provider ──────────────────────────────────────────

@test "detect_vcs_provider returns github for github.com remote" {
  mock_cmd git 0 "git@github.com:user/repo.git"
  run detect_vcs_provider
  assert_output "github"
}

@test "detect_vcs_provider returns gitlab for gitlab.com remote" {
  mock_cmd git 0 "git@gitlab.com:user/repo.git"
  run detect_vcs_provider
  assert_output "gitlab"
}

@test "detect_vcs_provider returns unknown with no git remote" {
  mock_cmd git 1 ""
  run detect_vcs_provider
  assert_output "unknown"
}

# ── get_vcs_pr_term ───────────────────────────────────────────────

@test "get_vcs_pr_term returns PR for github provider" {
  mock_cmd git 0 "git@github.com:user/repo.git"
  run get_vcs_pr_term
  assert_output "PR"
}

@test "get_vcs_pr_term returns MR for gitlab provider" {
  mock_cmd git 0 "git@gitlab.com:user/repo.git"
  run get_vcs_pr_term
  assert_output "MR"
}

# ── _inject_devflow_block (lib/init.sh) — idempotent CLAUDE.md block refresh (Phase E: E1) ──

@test "_inject_devflow_block replaces the existing devflow block (idempotent refresh)" {
  source_lib init.sh
  local f="${BATS_TEST_TMPDIR}/CLAUDE.md"
  printf 'pre\n<!-- devflow -->\nOLD\n<!-- /devflow -->\npost\n' > "$f"
  printf '<!-- devflow -->\nNEW RULE\n<!-- /devflow -->\n' > "${BATS_TEST_TMPDIR}/tmpl"
  _inject_devflow_block "$f" "${BATS_TEST_TMPDIR}/tmpl"
  run grep -c "NEW RULE" "$f"; assert_output "1"
  run grep -c "OLD" "$f";       assert_output "0"
  run grep -c "<!-- devflow -->" "$f"; assert_output "1"   # exactly one block
  run grep -c "^pre$" "$f"; assert_output "1"              # surrounding content preserved
}
