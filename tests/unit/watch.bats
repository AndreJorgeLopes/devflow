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
