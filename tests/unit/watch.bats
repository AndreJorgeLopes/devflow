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

# ── _detect_install_mode ───────────────────────────────────────

@test "detect_install_mode returns link for symlinked devflow" {
  # `command -v` skips dangling symlinks, so the target must actually exist
  # — otherwise the lookup falls through to a real devflow on PATH.
  local target="${BATS_TEST_TMPDIR}/real-devflow"
  printf '#!/bin/sh\n' > "$target"
  chmod +x "$target"
  ln -sf "$target" "${MOCK_DIR}/devflow"
  run _detect_install_mode
  assert_success
  assert_output "link"
}

@test "detect_install_mode returns install for regular file" {
  echo '#!/bin/bash' > "${MOCK_DIR}/devflow"
  chmod +x "${MOCK_DIR}/devflow"
  run _detect_install_mode
  assert_success
  assert_output "install"
}

@test "detect_install_mode returns brew for homebrew path" {
  mkdir -p "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin"
  echo '#!/bin/bash' > "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow"
  chmod +x "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow"
  ln -sf "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow" "${MOCK_DIR}/devflow"
  run _detect_install_mode
  assert_success
  assert_output "brew"
}

@test "detect_install_mode returns none when devflow not found anywhere" {
  # none now requires BOTH: not on PATH AND no launcher at any known location
  # (the pathless fallback resolves ~/.local/bin etc.), so use a clean empty HOME.
  export HOME="${BATS_TEST_TMPDIR}/empty-home"; mkdir -p "$HOME"
  rm -f "${MOCK_DIR}/devflow"
  DEVFLOW_ROOT="" PATH="${MOCK_DIR}" run _detect_install_mode
  assert_success
  assert_output "none"
}

# ── _auto_reinstall_check ─────────────────────────────────────

@test "auto_reinstall_check skips when not opted in" {
  local proj="${BATS_TEST_TMPDIR}/reinstall-test"
  mkdir -p "$proj/.devflow"
  echo "setup_at=2026-01-01" > "$proj/.devflow/.dev-setup"
  run _auto_reinstall_check "$proj" "" ""
  assert_success
  refute_output --partial "auto-updated"
}

@test "auto_reinstall_check skips when SHA matches" {
  local proj="${BATS_TEST_TMPDIR}/reinstall-match"
  mkdir -p "$proj/.devflow"
  echo "auto_reinstall=true" > "$proj/.devflow/.dev-setup"
  mkdir -p "${HOME}/.devflow"
  echo "abc1234" > "${HOME}/.devflow/.last-installed-sha"
  run _auto_reinstall_check "$proj" "abc1234" ""
  assert_success
  refute_output --partial "auto-updated"
  rm -f "${HOME}/.devflow/.last-installed-sha"
}

@test "auto_reinstall_check warns for brew install mode" {
  local proj="${BATS_TEST_TMPDIR}/reinstall-brew"
  mkdir -p "$proj/.devflow"
  echo "auto_reinstall=true" > "$proj/.devflow/.dev-setup"
  mkdir -p "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin"
  echo '#!/bin/bash' > "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow"
  chmod +x "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow"
  ln -sf "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow" "${MOCK_DIR}/devflow"
  run _auto_reinstall_check "$proj" "new-sha-123" ""
  assert_success
  assert_output --partial "Homebrew"
}

@test "auto_reinstall_check install mode: dry-run installs from a clean origin export" {
  local proj="${BATS_TEST_TMPDIR}/reinstall-install"
  mkdir -p "$proj/.devflow"
  echo "auto_reinstall=true" > "$proj/.devflow/.dev-setup"
  echo '#!/bin/bash' > "${MOCK_DIR}/devflow"      # regular file -> install (copy) mode
  chmod +x "${MOCK_DIR}/devflow"
  run _auto_reinstall_check "$proj" "new-sha-789" "" "1"
  assert_success
  assert_output --partial "clean export of origin/main"
}

@test "auto_reinstall_check install mode: a DIRTY source tree still installs (export ignores it, no staleness)" {
  local proj="${BATS_TEST_TMPDIR}/reinstall-install-dirty"
  mkdir -p "$proj/.devflow"
  echo "auto_reinstall=true" > "$proj/.devflow/.dev-setup"
  echo '#!/bin/bash' > "${MOCK_DIR}/devflow"
  chmod +x "${MOCK_DIR}/devflow"
  ( cd "$proj" && git init -q && git config user.email t@t && git config user.name t \
    && git add -A && git commit -qm init )
  echo "uncommitted junk" > "$proj/dirty.txt"     # dirty tree must NOT block or taint install
  run _auto_reinstall_check "$proj" "new-sha-789" "" "1"
  assert_success
  assert_output --partial "clean export of origin/main"   # installs from origin, not the dirty tree
  refute_output --partial "SKIP"
}

@test "auto_reinstall_check link mode: skips when tree is dirty (symlink can't be decoupled)" {
  local proj="${BATS_TEST_TMPDIR}/reinstall-link-dirty"
  mkdir -p "$proj/.devflow"
  echo "auto_reinstall=true" > "$proj/.devflow/.dev-setup"
  # symlink -> link (dev) mode; target is a plain file (not a brew path)
  echo '#!/bin/bash' > "${proj}/devflow-real"; chmod +x "${proj}/devflow-real"
  ln -sf "${proj}/devflow-real" "${MOCK_DIR}/devflow"
  ( cd "$proj" && git init -q && git config user.email t@t && git config user.name t \
    && git add -A && git commit -qm init )
  local sha; sha="$(git -C "$proj" rev-parse HEAD)"
  echo "uncommitted" > "$proj/dirty.txt"          # dirty -> link mode skips + notifies
  run _auto_reinstall_check "$proj" "$sha" "" "1"
  assert_success
  assert_output --partial "Would SKIP make link"
}

# ── macOS launchd scheduler backend ────────────────────────────

@test "launchd label is stable per project and distinct across projects" {
  local a b c
  a="$(_watch_launchd_label /tmp/projA)"
  b="$(_watch_launchd_label /tmp/projA)"
  c="$(_watch_launchd_label /tmp/projB)"
  [ "$a" = "$b" ] || fail "label not stable for same project ($a != $b)"
  [ "$a" != "$c" ] || fail "labels not distinct across projects"
  case "$a" in dev.devflow.watch.*) : ;; *) fail "unexpected label prefix: $a" ;; esac
}

@test "launchd install writes a LaunchAgent plist with a 5-min StartCalendarInterval" {
  export HOME="${BATS_TEST_TMPDIR}/lahome"; mkdir -p "$HOME"
  printf '#!/bin/bash\nexit 0\n' > "${MOCK_DIR}/launchctl"; chmod +x "${MOCK_DIR}/launchctl"
  run _watch_install_launchd "/tmp/myproj" "/Users/x/.local/bin/devflow"
  assert_success
  assert_output --partial "LaunchAgent installed"
  local plist; plist="$(_watch_launchd_plist /tmp/myproj)"
  [ -f "$plist" ] || fail "plist not written at $plist"
  run cat "$plist"
  assert_output --partial "<key>Label</key><string>dev.devflow.watch."
  assert_output --partial "<string>/Users/x/.local/bin/devflow</string>"
  assert_output --partial "<string>--headless</string>"
  assert_output --partial "<string>/tmp/myproj</string>"
  assert_output --partial "<key>StartCalendarInterval</key>"
  assert_output --partial "<key>RunAtLoad</key><true/>"
  # exactly 12 Minute entries = every 5 minutes; and NOT StartInterval (the sleep-miss bug)
  run bash -c "grep -c '<key>Minute</key>' '$plist'"
  assert_output "12"
  run bash -c "grep -c 'StartInterval</key>' '$plist' || true"
  assert_output "0"
}

@test "launchd remove unloads and deletes the plist" {
  export HOME="${BATS_TEST_TMPDIR}/lahome2"; mkdir -p "$HOME"
  printf '#!/bin/bash\nexit 0\n' > "${MOCK_DIR}/launchctl"; chmod +x "${MOCK_DIR}/launchctl"
  _watch_install_launchd "/tmp/proj2" "/bin/devflow"
  local plist; plist="$(_watch_launchd_plist /tmp/proj2)"
  [ -f "$plist" ] || fail "precondition: plist not written"
  run _watch_remove_launchd "/tmp/proj2"
  assert_success
  assert_output --partial "LaunchAgent removed"
  [ ! -f "$plist" ] || fail "plist not removed"
}

# ── _detect_install_mode under a minimal PATH (launchd/cron) ────

@test "detect_install_mode resolves WITHOUT PATH: copy install (regular file at BINDIR)" {
  export HOME="${BATS_TEST_TMPDIR}/dh-copy"; mkdir -p "$HOME/.local/bin"
  printf '#!/bin/bash\n' > "$HOME/.local/bin/devflow"; chmod +x "$HOME/.local/bin/devflow"
  PATH="/usr/bin:/bin" run _detect_install_mode
  assert_success
  assert_output "install"
}

@test "detect_install_mode resolves WITHOUT PATH: link (symlink at BINDIR)" {
  export HOME="${BATS_TEST_TMPDIR}/dh-link"; mkdir -p "$HOME/.local/bin"
  printf '#!/bin/bash\n' > "$HOME/real-df"; chmod +x "$HOME/real-df"
  ln -sf "$HOME/real-df" "$HOME/.local/bin/devflow"
  PATH="/usr/bin:/bin" run _detect_install_mode
  assert_success
  assert_output "link"
}

@test "detect_install_mode resolves WITHOUT PATH via DEVFLOW_ROOT for a custom prefix" {
  export HOME="${BATS_TEST_TMPDIR}/dh-none"; mkdir -p "$HOME"   # no ~/.local/bin/devflow
  local pfx="${BATS_TEST_TMPDIR}/opt/df"; mkdir -p "$pfx/bin" "$pfx/share/devflow"
  printf '#!/bin/bash\n' > "$pfx/bin/devflow"; chmod +x "$pfx/bin/devflow"
  DEVFLOW_ROOT="$pfx/share/devflow" PATH="/usr/bin:/bin" run _detect_install_mode
  assert_success
  assert_output "install"
}

@test "launchd plist injects PATH so the agent's minimal env can find devflow" {
  export HOME="${BATS_TEST_TMPDIR}/lah-path"; mkdir -p "$HOME"
  printf '#!/bin/bash\nexit 0\n' > "${MOCK_DIR}/launchctl"; chmod +x "${MOCK_DIR}/launchctl"
  _watch_install_launchd "/tmp/pp" "/Users/x/.local/bin/devflow"
  local plist; plist="$(_watch_launchd_plist /tmp/pp)"
  run cat "$plist"
  assert_output --partial "<key>EnvironmentVariables</key>"
  assert_output --partial "<key>PATH</key><string>/Users/x/.local/bin:"
}
