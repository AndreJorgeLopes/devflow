#!/usr/bin/env bats
# tests/unit/watch.bats — Unit tests for lib/watch.sh

setup() {
  load '../helpers/common'
  _common_setup
  load '../helpers/mocks'
  load '../helpers/assertions'
  source_lib utils.sh
  source_lib watch.sh

  # Create a temp config file for tests
  CONF_DIR="${BATS_TEST_TMPDIR}/.devflow"
  mkdir -p "$CONF_DIR"
  CONF_FILE="${CONF_DIR}/sensitive-files.conf"
}

teardown() {
  _common_teardown
}

# ── parse_sensitive_config ─────────────────────────────────────

@test "parse_sensitive_config parses mechanical entry correctly" {
  cat > "$CONF_FILE" <<'EOF'
mechanical | lib/utils.sh | Makefile | devflow check-version
EOF
  run parse_sensitive_config "$CONF_FILE"
  assert_success
  assert_output --partial "mechanical|lib/utils.sh|Makefile|devflow check-version"
}

@test "parse_sensitive_config skips comments and blank lines" {
  cat > "$CONF_FILE" <<'EOF'
# This is a comment

mechanical | lib/utils.sh | Makefile | devflow check-version
  # indented comment
EOF
  run parse_sensitive_config "$CONF_FILE"
  assert_success
  # Should only produce 1 entry
  local line_count
  line_count="$(echo "$output" | wc -l | tr -d ' ')"
  assert [ "$line_count" -eq 1 ]
}

@test "parse_sensitive_config parses semantic entry with prompt" {
  cat > "$CONF_FILE" <<'EOF'
semantic | CLAUDE.md | lib/*.sh,Makefile | Compare the Project Structure section against the actual file tree.
EOF
  run parse_sensitive_config "$CONF_FILE"
  assert_success
  assert_output --partial "semantic|CLAUDE.md|lib/*.sh,Makefile|Compare the Project Structure section against the actual file tree."
}

@test "parse_sensitive_config returns empty for missing file" {
  run parse_sensitive_config "/nonexistent/file.conf"
  assert_success
  assert_output ""
}

@test "parse_sensitive_config handles multiple entries" {
  cat > "$CONF_FILE" <<'EOF'
mechanical | lib/utils.sh | Makefile | devflow check-version
mechanical | plugin.json | Makefile | devflow check-version
semantic | README.md | install.sh | Check install instructions.
EOF
  run parse_sensitive_config "$CONF_FILE"
  assert_success
  local line_count
  line_count="$(echo "$output" | wc -l | tr -d ' ')"
  assert [ "$line_count" -eq 3 ]
}

# ── match_sources ──────────────────────────────────────────────

@test "match_sources matches exact filename" {
  local changed_files="Makefile
lib/utils.sh"
  local sources="Makefile"
  run match_sources "$sources" "$changed_files"
  assert_success
}

@test "match_sources matches glob pattern" {
  local changed_files="lib/watch.sh
lib/utils.sh"
  local sources="lib/*.sh"
  run match_sources "$sources" "$changed_files"
  assert_success
}

@test "match_sources matches comma-separated sources" {
  local changed_files="install.sh"
  local sources="Makefile,install.sh"
  run match_sources "$sources" "$changed_files"
  assert_success
}

@test "match_sources returns failure when no match" {
  local changed_files="README.md
docs/plan.md"
  local sources="lib/*.sh,Makefile"
  run match_sources "$sources" "$changed_files"
  assert_failure
}

@test "match_sources handles nested glob patterns" {
  local changed_files="lib/hooks/prompt-fetch-rebase.sh"
  local sources="lib/hooks/*.sh"
  run match_sources "$sources" "$changed_files"
  assert_success
}

# ── get_flagged_targets ────────────────────────────────────────

@test "get_flagged_targets returns targets with matching sources" {
  cat > "$CONF_FILE" <<'EOF'
mechanical | lib/utils.sh | Makefile | devflow check-version
mechanical | plugin.json | Makefile | devflow check-version
semantic | README.md | install.sh | Check instructions.
EOF
  local changed_files="Makefile"
  run get_flagged_targets "$CONF_FILE" "$changed_files"
  assert_success
  assert_output --partial "lib/utils.sh"
  assert_output --partial "plugin.json"
  refute_output --partial "README.md"
}

@test "get_flagged_targets returns empty when no sources match" {
  cat > "$CONF_FILE" <<'EOF'
mechanical | lib/utils.sh | Makefile | devflow check-version
EOF
  local changed_files="README.md"
  run get_flagged_targets "$CONF_FILE" "$changed_files"
  assert_success
  assert_output ""
}

# ── check_version_consistency ──────────────────────────────────

@test "check_version_consistency passes when all versions match" {
  # Create a mock project structure in tmp
  local proj="${BATS_TEST_TMPDIR}/project"
  mkdir -p "$proj/lib" "$proj/devflow-plugin/.claude-plugin" "$proj/devflow-plugin/commands"

  cat > "$proj/Makefile" <<'EOF'
VERSION := 1.2.3
EOF
  cat > "$proj/lib/utils.sh" <<'EOF'
DEVFLOW_VERSION="1.2.3"
EOF
  cat > "$proj/devflow-plugin/.claude-plugin/plugin.json" <<'EOF'
{ "version": "1.2.3" }
EOF
  cat > "$proj/devflow-plugin/.claude-plugin/marketplace.json" <<'EOF'
{ "version": "1.2.3" }
EOF
  cat > "$proj/devflow-plugin/commands/test.md" <<'EOF'
---
description: [devflow v1.2.3] Test command
---
EOF

  run check_version_consistency "$proj"
  assert_success
}

@test "check_version_consistency fails when utils.sh version differs" {
  local proj="${BATS_TEST_TMPDIR}/project2"
  mkdir -p "$proj/lib" "$proj/devflow-plugin/.claude-plugin" "$proj/devflow-plugin/commands"

  cat > "$proj/Makefile" <<'EOF'
VERSION := 1.2.3
EOF
  cat > "$proj/lib/utils.sh" <<'EOF'
DEVFLOW_VERSION="1.0.0"
EOF
  cat > "$proj/devflow-plugin/.claude-plugin/plugin.json" <<'EOF'
{ "version": "1.2.3" }
EOF
  cat > "$proj/devflow-plugin/.claude-plugin/marketplace.json" <<'EOF'
{ "version": "1.2.3" }
EOF

  run check_version_consistency "$proj"
  assert_failure
  assert_output --partial "lib/utils.sh"
  assert_output --partial "1.0.0"
}

# ── devflow_watch (dry-run) ────────────────────────────────────

@test "devflow_watch exits 0 when config file is missing" {
  # Ensure no config file exists
  rm -f "${BATS_TEST_TMPDIR}/.devflow/sensitive-files.conf"
  run devflow_watch --dry-run --project "${BATS_TEST_TMPDIR}"
  assert_success
  assert_output --partial "No sensitive-files.conf"
}
