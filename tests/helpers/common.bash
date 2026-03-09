#!/usr/bin/env bash
# tests/helpers/common.bash — Shared setup/teardown for all bats tests

# Determine devflow root once (two levels up from tests/<category>/)
_DEVFLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Load bats helper libraries (git submodules in tests/lib/)
load "${_DEVFLOW_ROOT}/tests/lib/bats-support/load"
load "${_DEVFLOW_ROOT}/tests/lib/bats-assert/load"

# _common_setup — call from setup() in each test file
_common_setup() {
  # Export project paths
  DEVFLOW_ROOT="$_DEVFLOW_ROOT"
  PROJECT_ROOT="$DEVFLOW_ROOT"
  export DEVFLOW_ROOT PROJECT_ROOT

  # Create mock directory and prepend to PATH for isolation
  MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
  mkdir -p "$MOCK_DIR"
  _ORIGINAL_PATH="$PATH"
  export PATH="${MOCK_DIR}:${PATH}"
}

# _common_teardown — call from teardown() in each test file
_common_teardown() {
  PATH="$_ORIGINAL_PATH"
  export PATH
}

# source_lib <name> — source a lib/*.sh file relative to devflow root
source_lib() {
  local lib_name="$1"
  source "${DEVFLOW_ROOT}/lib/${lib_name}"
}
