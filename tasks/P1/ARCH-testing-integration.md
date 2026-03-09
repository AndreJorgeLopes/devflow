---
id: ARCH-testing-integration
title: "Integration Tests — CLI Commands and Flows"
priority: P1
category: architecture
status: open
depends_on:
  - ARCH-testing-foundation
estimated_effort: M
files_to_touch:
  - Makefile
  - tests/integration/cli-commands.bats
  - tests/integration/check-flow.bats
  - tests/integration/init-flow.bats
  - tests/integration/skills-flow.bats
  - tests/integration/plugin-dev.bats
---

# Integration Tests — CLI Commands and Flows

## Context

Phase 3 of the testing infrastructure buildout (parent: `ARCH-testing-infrastructure`). Depends on `ARCH-testing-foundation` for bats-core and helpers.

Unlike unit tests (Phase 2) which source `lib/*.sh` directly and test individual functions, integration tests invoke `bin/devflow` as a subprocess and verify the full command dispatching, argument parsing, and output formatting. These tests exercise the same code paths that agents and developers use when running `devflow check`, `devflow init`, or `devflow skills convert`.

## Steps

1. **Create `tests/integration/cli-commands.bats`** — test every devflow subcommand
   - `devflow help` exits 0 and outputs usage info
   - `devflow --help` exits 0 (alias)
   - `devflow version` exits 0 and outputs a version string matching `[0-9]+\.[0-9]+\.[0-9]+`
   - `devflow --version` exits 0 (alias)
   - `devflow status` exits 0 and outputs layer status
   - `devflow check` exits appropriately (may need mocked CLI or staged diff)
   - `devflow skills` exits 0 and outputs subcommand help
   - `devflow init` exits appropriately in a temp dir
   - `devflow nonexistent` exits non-zero with an error message
   - `devflow` with no args exits 0 and shows help

2. **Create `tests/integration/check-flow.bats`** — end-to-end `devflow check` with mocks
   - Set up a temp git repo with staged changes and `.devflow/checks/` rules
   - Mock `claude` CLI: verify it receives `--print`, `--system-prompt` with rules content, `--permission-mode`, and diff on stdin
   - Run `devflow check` and assert it exits 0 with review output
   - Mock only `opencode` (no claude): verify fallback to `opencode run` with combined prompt
   - Test with `DEVFLOW_REVIEW_CLI` env override
   - Test with no staged diff: verify appropriate error/warning message
   - Test with no CLI available: verify error message

3. **Create `tests/integration/init-flow.bats`** — `devflow init` in an isolated temp dir
   - Run `devflow init` in a fresh temp directory
   - Assert `.devflow/checks/` directory is created with default rule files
   - Assert symlinks are created (mock HOME to temp dir)
   - Assert summary output lists detected tools correctly
   - Run `devflow init` a second time: verify idempotent behavior (no errors, no duplicates)
   - Test init with various tool combinations (only claude, only opencode, both, neither)

4. **Create `tests/integration/skills-flow.bats`** — skills lifecycle
   - `devflow skills list` outputs registered skills with expected format
   - `devflow skills install <skill>` installs a skill (using fixtures)
   - `devflow skills convert` generates plugin structure
   - Verify generated plugin structure has expected files
   - If `claude` is mocked, verify `claude plugin validate` would be called correctly

5. **Create `tests/integration/plugin-dev.bats`** — Makefile plugin targets
   - `make plugin-dev` creates expected symlinks at `~/.claude/commands/devflow` and `~/.claude/skills/devflow-recall` (mock HOME)
   - `make plugin-unlink` removes the symlinks
   - `make plugin-install` runs without error (may need mocked `claude` CLI)
   - Verify symlinks point to correct targets
   - Test that `make plugin-dev` is idempotent (running twice doesn't error)

6. **Add `test-integration` Makefile target**
   - Target: `bats tests/integration/`
   - Ensure it's independent of `test-unit` (can run separately)

## Key Test Scenarios

### CLI Command Dispatch

| Command | Expected Exit | Expected Output |
|---------|---------------|-----------------|
| `devflow help` | 0 | Contains "Usage" |
| `devflow --help` | 0 | Contains "Usage" |
| `devflow version` | 0 | Matches `v?[0-9]+\.[0-9]+\.[0-9]+` |
| `devflow status` | 0 | Contains "Layer" or status info |
| `devflow nonexistent` | non-zero | Contains "unknown" or "error" |
| `devflow` (no args) | 0 | Contains "Usage" |

### Check Flow

| Scenario | Setup | Expected |
|----------|-------|----------|
| claude available | mock claude, staged diff, check rules | claude called with --system-prompt, exits 0 |
| opencode fallback | mock opencode only, staged diff | opencode called, exits 0 |
| env override | `DEVFLOW_REVIEW_CLI=opencode`, both mocked | opencode used despite claude available |
| no diff | no staged changes | warning/error message |
| no CLI | no mocks | error message, non-zero exit |

### Plugin Dev Workflow

| Scenario | Setup | Expected |
|----------|-------|----------|
| plugin-dev creates links | mock HOME | symlinks at expected paths |
| plugin-unlink removes | after plugin-dev | symlinks removed |
| plugin-dev idempotent | run twice | no errors |

## Acceptance Criteria

- [ ] `tests/integration/cli-commands.bats` tests all devflow subcommands (8+ tests)
- [ ] `tests/integration/check-flow.bats` tests check with claude mock, opencode fallback, env override, no diff, no CLI (5+ tests)
- [ ] `tests/integration/init-flow.bats` tests init lifecycle including idempotency (4+ tests)
- [ ] `tests/integration/skills-flow.bats` tests list/install/convert (3+ tests)
- [ ] `tests/integration/plugin-dev.bats` tests Makefile plugin targets (3+ tests)
- [ ] `make test-integration` runs 15+ tests, all pass
- [ ] All tests use mocked external tools (no real claude/opencode/docker calls)
- [ ] Tests create and clean up their own temp directories

## Verification

```bash
# Integration tests pass
make test-integration

# Individual test files run cleanly
bats tests/integration/cli-commands.bats
bats tests/integration/check-flow.bats
bats tests/integration/init-flow.bats
bats tests/integration/skills-flow.bats
bats tests/integration/plugin-dev.bats

# Test count check (should be 15+)
bats tests/integration/ 2>&1 | tail -1
```

## Workflow Integration

These tests validate the full CLI surface that agents interact with daily. When an agent runs `devflow check` inside `pre-push-check` or `finish-feature`, these tests prove that command works correctly with the expected arguments and output format.

The `check-flow.bats` tests are particularly important — they verify the exact same code path that runs when `devflow check` is invoked by the `pre-push-check`, `create-pr`, and `finish-feature` skills. If these tests pass, we know the Code Review pipeline is working.

The `plugin-dev.bats` tests validate the symlink dev workflow from `ARCH-plugin-dev-workflow`. Developers run `make plugin-dev` daily to set up their local environment — these tests catch breakage before it reaches anyone's machine.
