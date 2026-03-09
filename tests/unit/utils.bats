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
  assert [ -d "${output}/.git" ]
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
