#!/usr/bin/env bats
# tests/unit/requirements.bats — per-skill requirements.json schema + registry mirror
# Phase B: B1 (schema / hindsight-optional / node+npm / dep keys), B4 (registry mirror).

load '../helpers/common'
load '../helpers/assertions'

setup() { REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"; }

@test "every in-scope skill has a valid requirements.json with skill/required/optional keys" {
  for s in render-diagram review review-document best-roi-task; do
    local f="${REPO}/skills/${s}/requirements.json"
    assert [ -f "$f" ]
    run jq -e '.skill and (.required|type=="array") and (.optional|type=="array")' "$f"
    assert_success
  done
}

@test "hindsight is declared OPTIONAL (never required) wherever it appears" {
  # found-guard keeps this RED-correct: with no requirements.json yet, the glob stays
  # literal and the loop is skipped, so found=0 fails. At GREEN the glob also covers
  # write-spike's file (added in Phase C), enforcing "hindsight optional everywhere".
  local found=0 f
  for f in "${REPO}"/skills/*/requirements.json; do
    [ -f "$f" ] || continue
    found=1
    run jq -e '[.required[]?.name] | index("hindsight")' "$f"
    assert_failure   # hindsight must NOT be in required[]
  done
  assert [ "$found" -ge 1 ]
}

@test "render-diagram requires node and npm" {
  run jq -e '[.required[].name] | (index("node") and index("npm"))' "${REPO}/skills/render-diagram/requirements.json"
  assert_success
}

@test "each dep has name, check, why" {
  local found=0 f
  for f in "${REPO}"/skills/*/requirements.json; do
    [ -f "$f" ] || continue
    found=1
    run jq -e '[.required[],.optional[]] | all(has("name") and has("check") and has("why"))' "$f"
    assert_success
  done
  assert [ "$found" -ge 1 ]
}

@test "registry mirrors requires/optional name-lists for in-scope skills" {
  for s in render-diagram review review-document best-roi-task; do
    run jq -e --arg s "$s" '.skills[] | select(.name==$s) | (.requires|type=="array") and (.optional|type=="array")' "${REPO}/skills/registry.json"
    assert_success
  done
}
