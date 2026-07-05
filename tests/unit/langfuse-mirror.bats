#!/usr/bin/env bats
# Unit tests for lib/langfuse-mirror.sh — the SKILL.md -> Langfuse prompt mirror (component b).
# These do NOT need a live Langfuse: pointing LANGFUSE_HOST at an unreachable port makes the
# "current version" fetch return empty, so every skill is reported as a would-push under dry-run.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/langfuse-mirror.sh"
  export LANGFUSE_PUBLIC_KEY="pk-test"
  export LANGFUSE_SECRET_KEY="sk-test"
  export LANGFUSE_HOST="http://127.0.0.1:59999"   # nothing listening -> fetch returns empty
  # Neutralize a real secrets file so it cannot override the unreachable host above.
  export HOME="$BATS_TEST_TMPDIR"
}

@test "mirror --dry-run reports a would-push for a single skill and never writes" {
  run langfuse_mirror --name resolve-repo --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"skill/resolve-repo (would push new version)"* ]]
  [[ "$output" == *"(dry-run)"* ]]
  [[ "$output" == *"1 skill(s)"* ]]
}

@test "mirror rejects an unknown flag with usage (exit 2)" {
  run langfuse_mirror --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: devflow skills mirror"* ]]
}

@test "mirror fails clearly when Langfuse keys are absent" {
  unset LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY
  run langfuse_mirror --name resolve-repo --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"LANGFUSE_PUBLIC_KEY"* ]]
}

@test "mirror --dry-run over all skills reports the full source count" {
  run langfuse_mirror --dry-run
  [ "$status" -eq 0 ]
  # At least the 28 pre-trace-review skills plus trace-review; assert it saw a plausible count.
  [[ "$output" =~ [0-9]+" skill(s)" ]]
  [[ "$output" == *"(dry-run)"* ]]
}
