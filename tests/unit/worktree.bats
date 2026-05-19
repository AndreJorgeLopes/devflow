#!/usr/bin/env bats
# tests/unit/worktree.bats — Unit tests for lib/worktree.sh

setup() {
  load '../helpers/common'
  _common_setup
  load '../helpers/mocks'
  load '../helpers/assertions'
  source_lib utils.sh
  source_lib worktree.sh

  # Hermetic: stub _ensure_main_unlocked so tests don't run real git against the host repo.
  _ensure_main_unlocked() { :; }

  # Guard: fail loudly if any code path re-wires agent-deck into devflow_worktree.
  cat > "${MOCK_DIR}/agent-deck" <<'EOF'
#!/usr/bin/env bash
echo "ERROR: agent-deck was invoked from devflow_worktree" >&2
exit 99
EOF
  chmod +x "${MOCK_DIR}/agent-deck"
}

teardown() {
  _common_teardown
}

# ── branch-name enforcement ───────────────────────────────────────

@test "devflow_worktree rejects empty name with usage message" {
  run devflow_worktree
  assert_failure
  assert_output --partial "Usage: devflow worktree <name>"
}

@test "devflow_worktree accepts ticket-shaped name (MES-1234)" {
  # Mock wt to echo its args so we can assert the normalized branch arrived unmodified.
  cat > "${MOCK_DIR}/wt" <<'EOF'
#!/usr/bin/env bash
echo "wt called with: $*"
exit 0
EOF
  chmod +x "${MOCK_DIR}/wt"

  run devflow_worktree MES-1234
  assert_success
  assert_output --partial "Creating worktree: MES-1234"
  assert_output --partial "switch --create MES-1234"
  refute_output --partial "feat/"
}

@test "devflow_worktree accepts free-form name and prefixes feat/" {
  cat > "${MOCK_DIR}/wt" <<'EOF'
#!/usr/bin/env bash
echo "wt called with: $*"
exit 0
EOF
  chmod +x "${MOCK_DIR}/wt"

  run devflow_worktree add-user-metrics
  assert_success
  assert_output --partial "feat/add-user-metrics"
}

# ── --agent deprecation ───────────────────────────────────────────

@test "devflow_worktree rejects --agent with deprecation message" {
  run devflow_worktree MES-1234 --agent claude
  assert_failure
  assert_output --partial "--agent flag removed: agent-deck is no longer wired into devflow"
}

@test "devflow_worktree rejects --agent=value with deprecation message" {
  run devflow_worktree MES-1234 --agent=claude
  assert_failure
  assert_output --partial "--agent flag removed: agent-deck is no longer wired into devflow"
}

# ── branch-name edge cases (regression tests for C2/C3) ───────────

@test "devflow_worktree preserves lowercase ticket-shaped name (mes-1234)" {
  cat > "${MOCK_DIR}/wt" <<'EOF'
#!/usr/bin/env bash
echo "wt called with: $*"
exit 0
EOF
  chmod +x "${MOCK_DIR}/wt"

  run devflow_worktree mes-1234
  assert_success
  assert_output --partial "switch --create mes-1234"
  refute_output --partial "feat/mes-1234"
}

@test "devflow_worktree does not double-prefix slash-containing name (feat/already-prefixed)" {
  cat > "${MOCK_DIR}/wt" <<'EOF'
#!/usr/bin/env bash
echo "wt called with: $*"
exit 0
EOF
  chmod +x "${MOCK_DIR}/wt"

  run devflow_worktree feat/already-prefixed
  assert_success
  assert_output --partial "switch --create feat/already-prefixed"
  refute_output --partial "feat/feat/"
}

@test "devflow_worktree passes underscore ticket (MES_1234) through with feat/ prefix" {
  # Documents current behavior — underscore is NOT treated as ticket-shaped.
  # If the team later wants underscore support, change the regex and this test.
  cat > "${MOCK_DIR}/wt" <<'EOF'
#!/usr/bin/env bash
echo "wt called with: $*"
exit 0
EOF
  chmod +x "${MOCK_DIR}/wt"

  run devflow_worktree MES_1234
  assert_success
  assert_output --partial "switch --create feat/MES_1234"
}

@test "devflow_worktree surfaces wt failure with die message (regression for silent set -e exit)" {
  # Mock wt to exit 1 — must produce a "Failed to create worktree" message
  # and a non-zero exit code (not a silent shell exit).
  cat > "${MOCK_DIR}/wt" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${MOCK_DIR}/wt"

  run devflow_worktree MES-9999
  assert_failure
  assert_output --partial "Failed to create worktree"
}
