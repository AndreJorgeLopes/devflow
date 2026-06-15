#!/usr/bin/env bats
# tests/unit/deps.bats — `devflow deps check <skill>` preflight accelerator (Phase B: B3).

load '../helpers/common'
load '../helpers/assertions'
load '../helpers/mocks'

setup() { REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"; }

@test "deps check reports OK when all required present" {
  run "${REPO}/bin/devflow" deps check render-diagram
  assert_success
  assert_output --partial "render-diagram"
}

@test "deps check exits non-zero and names the dep when a required dep is missing" {
  # Parser-level test against a fixture with an impossible required check (avoids having
  # to hide a real binary like node from command resolution).
  local tmp="${BATS_TEST_TMPDIR}/req.json"
  printf '{"skill":"x","required":[{"name":"definitely_absent_bin_xyz","check":"definitely_absent_bin_xyz --v","why":"w","install":"i"}],"optional":[]}' > "$tmp"
  run "${REPO}/bin/devflow" deps check --file "$tmp"
  assert_failure
  assert_output --partial "definitely_absent_bin_xyz"
}
