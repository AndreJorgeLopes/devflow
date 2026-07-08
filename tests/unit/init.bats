#!/usr/bin/env bats
# tests/unit/init.bats — Unit tests for lib/init.sh settings registration
#
# Focus: _register_settings must never abort `devflow init` and never leave the
# user's ~/.claude/settings.json truncated. Two robustness properties:
#   1. Atomic write — a temp file in the same dir + os.replace, so a crash
#      mid-write cannot corrupt the live file (observable surface: no leftover
#      temp files after a successful write; the result is always valid JSON).
#   2. Malformed-input recovery — a pre-existing settings.json that is not valid
#      JSON is backed up and rebuilt from an empty config, with a WARN, instead
#      of raising a traceback that would abort init under `set -euo pipefail`.

setup() {
  load '../helpers/common'
  _common_setup
  load '../helpers/mocks'
  source_lib init.sh
}

teardown() {
  _common_teardown
}

# ── malformed-input recovery ──────────────────────────────────────

@test "_register_settings hooks survives a malformed settings.json (backup + rebuild)" {
  local sf="${BATS_TEST_TMPDIR}/settings.json"
  printf '{ this is not valid json' > "$sf"

  run _register_settings hooks "$sf" "$DEVFLOW_ROOT"
  assert_success
  assert_output --partial "WARN:"

  # Original bytes preserved in a timestamped backup
  run bash -c "cat ${BATS_TEST_TMPDIR}/settings.json.corrupt-*.bak"
  assert_output --partial "this is not valid json"

  # settings.json is now valid JSON carrying the devflow hooks
  run python3 -c "import json; d=json.load(open('$sf')); print('Stop' in d.get('hooks', {}))"
  assert_output "True"

  # No leftover temp files from the atomic write
  run bash -c "ls ${BATS_TEST_TMPDIR}/.settings-*.tmp 2>/dev/null | wc -l | tr -d ' '"
  assert_output "0"
}

@test "_register_settings marketplace survives a malformed settings.json" {
  local sf="${BATS_TEST_TMPDIR}/settings.json"
  printf 'not json at all' > "$sf"

  run _register_settings marketplace "$sf" "$DEVFLOW_ROOT" false
  assert_success
  assert_output --partial "WARN:"

  run python3 -c "import json; d=json.load(open('$sf')); print('devflow-marketplace' in d.get('extraKnownMarketplaces', {}))"
  assert_output "True"
}

# ── happy path (valid input is untouched apart from our keys) ──────

@test "_register_settings hooks preserves existing keys and creates no backup on valid JSON" {
  local sf="${BATS_TEST_TMPDIR}/settings.json"
  printf '{"env":{"FOO":"bar"}}\n' > "$sf"

  run _register_settings hooks "$sf" "$DEVFLOW_ROOT"
  assert_success
  refute_output --partial "WARN:"

  # Existing user key survives
  run python3 -c "import json; d=json.load(open('$sf')); print(d['env']['FOO'])"
  assert_output "bar"

  # No backup created for valid input
  run bash -c "ls ${BATS_TEST_TMPDIR}/settings.json.corrupt-*.bak 2>/dev/null | wc -l | tr -d ' '"
  assert_output "0"
}

@test "_register_settings hooks is idempotent (second run reports Skip, no rewrite churn)" {
  local sf="${BATS_TEST_TMPDIR}/settings.json"
  printf '{}\n' > "$sf"

  run _register_settings hooks "$sf" "$DEVFLOW_ROOT"
  assert_success
  assert_output --partial "Added"

  run _register_settings hooks "$sf" "$DEVFLOW_ROOT"
  assert_success
  assert_output --partial "Skip"
  refute_output --partial "Added"
}

# ── make install: symlink-safe (regression for the write-through-symlink bug) ──

@test "make install replaces a leftover 'make link' symlink instead of writing through it" {
  local prefix="${BATS_TEST_TMPDIR}/prefix"
  mkdir -p "$prefix/bin"
  # sentinel standing in for the source bin/devflow a leftover symlink would point at
  local sentinel="${BATS_TEST_TMPDIR}/source-bin-devflow"
  printf 'FULL SOURCE SCRIPT — must not be overwritten\n' > "$sentinel"
  ln -sf "$sentinel" "$prefix/bin/devflow"        # leftover `make link` symlink

  run make -C "$DEVFLOW_ROOT" install PREFIX="$prefix"
  assert_success

  # BINDIR/devflow must be a REAL launcher now, not the symlink...
  [ ! -L "$prefix/bin/devflow" ] || fail "BINDIR/devflow is still a symlink (wrote through it)"
  # ...and the symlink target (stand-in for the source checkout) must be UNTOUCHED
  run cat "$sentinel"
  assert_output --partial "FULL SOURCE SCRIPT"
}
