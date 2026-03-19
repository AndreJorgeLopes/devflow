#!/usr/bin/env bats
# tests/unit/release.bats — Unit tests for lib/release.sh

setup() {
  load '../helpers/common'
  _common_setup
  load '../helpers/mocks'
  load '../helpers/assertions'
  source_lib utils.sh
  source_lib release.sh

  # Create a temp git repo for testing
  TEST_REPO="${BATS_TEST_TMPDIR}/test-repo"
  mkdir -p "$TEST_REPO"
  git -C "$TEST_REPO" init --quiet
  git -C "$TEST_REPO" config user.email "test@test.com"
  git -C "$TEST_REPO" config user.name "Test"
  # Initial commit
  echo "init" > "$TEST_REPO/file.txt"
  git -C "$TEST_REPO" add .
  git -C "$TEST_REPO" commit -m "chore: initial commit" --quiet
  git -C "$TEST_REPO" tag v0.1.0
}

teardown() {
  _common_teardown
}

# ── _parse_conventional_commits ────────────────────────────────

@test "parse_conventional_commits returns minor for feat: commits" {
  echo "feature" > "$TEST_REPO/feature.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "feat: add new feature" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "minor"
}

@test "parse_conventional_commits returns patch for fix: commits" {
  echo "fix" > "$TEST_REPO/fix.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "fix: resolve a bug" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "patch"
}

@test "parse_conventional_commits returns major for feat!: commits" {
  echo "breaking" > "$TEST_REPO/break.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "feat!: breaking API change" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "major"
}

@test "parse_conventional_commits returns major for BREAKING CHANGE footer" {
  echo "breaking2" > "$TEST_REPO/break2.txt"
  git -C "$TEST_REPO" add .
  git -C "$TEST_REPO" commit -m "feat: new api

BREAKING CHANGE: removes old endpoint" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "major"
}

@test "parse_conventional_commits returns none for only chore: commits" {
  echo "chore" > "$TEST_REPO/chore.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "chore: update deps" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "none"
}

@test "parse_conventional_commits returns none for [skip release]" {
  echo "feat" > "$TEST_REPO/feat.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "feat: add thing [skip release]" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "none"
}

@test "parse_conventional_commits picks highest bump (feat > fix)" {
  echo "fix" > "$TEST_REPO/fix.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "fix: bug fix" --quiet
  echo "feat" > "$TEST_REPO/feat.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "feat: new feature" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "minor"
}

@test "parse_conventional_commits handles first release (no previous tag)" {
  # Create a repo with no tags
  local fresh_repo="${BATS_TEST_TMPDIR}/fresh-repo"
  mkdir -p "$fresh_repo"
  git -C "$fresh_repo" init --quiet
  git -C "$fresh_repo" config user.email "test@test.com"
  git -C "$fresh_repo" config user.name "Test"
  echo "init" > "$fresh_repo/file.txt"
  git -C "$fresh_repo" add .
  git -C "$fresh_repo" commit -m "feat: initial feature" --quiet
  run _parse_conventional_commits "$fresh_repo"
  assert_success
  assert_line --index 0 "minor"
}

# ── _semver_bump ───────────────────────────────────────────────

@test "semver_bump minor: 0.1.0 → 0.2.0" {
  run _semver_bump "0.1.0" "minor"
  assert_success
  assert_output "0.2.0"
}

@test "semver_bump patch: 0.1.0 → 0.1.1" {
  run _semver_bump "0.1.0" "patch"
  assert_success
  assert_output "0.1.1"
}

@test "semver_bump major: 0.1.0 → 1.0.0" {
  run _semver_bump "0.1.0" "major"
  assert_success
  assert_output "1.0.0"
}

@test "semver_bump minor: 1.9.3 → 1.10.0" {
  run _semver_bump "1.9.3" "minor"
  assert_success
  assert_output "1.10.0"
}

@test "semver_bump returns error for none" {
  run _semver_bump "0.1.0" "none"
  assert_failure
}
