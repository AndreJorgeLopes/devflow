---
id: ARCH-testing-foundation
title: "Testing Foundation — bats-core, Helpers, First Unit Test"
priority: P1
category: architecture
status: open
depends_on: []
estimated_effort: S
files_to_touch:
  - Makefile
  - tests/helpers/common.bash
  - tests/helpers/mocks.bash
  - tests/helpers/assertions.bash
  - tests/unit/utils.bats
  - tests/fixtures/
---

# Testing Foundation — bats-core, Helpers, First Unit Test

## Context

Phase 1 of the testing infrastructure buildout (parent: `ARCH-testing-infrastructure`).

Devflow has zero automated tests beyond 3 Makefile smoke checks. This task bootstraps the entire testing foundation: framework installation, helper libraries, directory structure, and the first real unit test file. Every subsequent testing task depends on this one.

## Steps

1. **Install bats-core and companion libraries**
   - `brew install bats-core`
   - Install `bats-support` and `bats-assert` as git submodules or via brew
   - Verify: `bats --version` succeeds

2. **Create `tests/` directory structure**
   ```
   tests/
   ├── helpers/
   ├── fixtures/
   ├── unit/
   ├── integration/
   └── e2e/
   ```

3. **Create `tests/helpers/common.bash`**
   - Shared `setup()` function: create temp dir, save original PATH, source `lib/utils.sh`
   - Shared `teardown()` function: restore PATH, clean temp dirs
   - PATH isolation: prepend mock dir to PATH so tests never call real external tools
   - Helper to source any `lib/*.sh` file relative to project root
   - `DEVFLOW_ROOT` and `PROJECT_ROOT` env vars pointing to the repo

4. **Create `tests/helpers/mocks.bash`**
   - `mock_cmd` function: creates a stub executable in `$BATS_TEST_TMPDIR/mocks/`
   - Accepts: command name, exit code (default 0), stdout output (default empty)
   - Stub is added to front of PATH so it shadows real commands
   - `mock_cmd_with_args` variant: records arguments to a file for later assertion
   - `assert_mock_called_with` helper: checks recorded arguments

5. **Create `tests/helpers/assertions.bash`**
   - `assert_line_contains` — check that a specific line in output contains a substring
   - `assert_file_exists` — check file exists at path
   - `assert_file_contains` — check file contains a string
   - `assert_symlink_to` — check that a path is a symlink pointing to expected target

6. **Write `tests/unit/utils.bats`** — first real test file
   - Test `has_cmd` with a real command (bash) and a fake command
   - Test `project_root` returns a valid directory
   - Test `devflow_root` returns the devflow install directory
   - Test `detect_vcs_provider` returns `github` for a github.com remote
   - Test `detect_vcs_provider` returns `gitlab` for a gitlab.com remote
   - Test `get_vcs_pr_term` returns `PR` for github provider
   - Test `get_vcs_pr_term` returns `MR` for gitlab provider
   - Test edge case: `detect_vcs_provider` with no git remote

7. **Update Makefile**
   - Add `test-unit` target: `bats tests/unit/`
   - Keep existing smoke tests as-is (they'll be replaced in Phase 4)

8. **Create minimal fixtures**
   - `tests/fixtures/.gitkeep` files for subdirectories
   - `tests/fixtures/diff-samples/simple.diff` — a basic git diff for later use

## Key Test Scenarios

| Test | Function | Expected |
|------|----------|----------|
| `has_cmd` with `bash` | `has_cmd bash` | returns 0 |
| `has_cmd` with fake cmd | `has_cmd nonexistent_xyz` | returns 1 |
| `project_root` in repo | `project_root` | returns dir containing `.git` |
| `devflow_root` | `devflow_root` | returns dir containing `bin/devflow` |
| `detect_vcs_provider` github | mock git remote with `github.com` | outputs `github` |
| `detect_vcs_provider` gitlab | mock git remote with `gitlab.com` | outputs `gitlab` |
| `get_vcs_pr_term` github | `get_vcs_pr_term github` | outputs `PR` |
| `get_vcs_pr_term` gitlab | `get_vcs_pr_term gitlab` | outputs `MR` |

## Acceptance Criteria

- [ ] `bats --version` succeeds (framework installed)
- [ ] `tests/` directory structure exists with helpers/, fixtures/, unit/, integration/, e2e/
- [ ] `tests/helpers/common.bash` provides setup/teardown with PATH isolation
- [ ] `tests/helpers/mocks.bash` provides `mock_cmd` function
- [ ] `tests/helpers/assertions.bash` provides custom assertion helpers
- [ ] `tests/unit/utils.bats` has 8+ tests covering `has_cmd`, `project_root`, `devflow_root`, `detect_vcs_provider`, `get_vcs_pr_term`
- [ ] `make test-unit` runs all tests and passes
- [ ] No test calls a real external tool (claude, opencode, docker, etc.)

## Verification

```bash
# Framework available
bats --version

# Directory structure exists
ls tests/helpers/ tests/fixtures/ tests/unit/ tests/integration/ tests/e2e/

# Unit tests pass
make test-unit

# Specific test file runs
bats tests/unit/utils.bats
```

## Workflow Integration

This is the entry point for the entire testing effort. An agent session starts here with `/devflow:new-feature` → brainstorming → writing-plans → executing-plans.

Once this phase lands, every subsequent testing task can run `make test-unit` in its verification step. The helpers created here (`common.bash`, `mocks.bash`, `assertions.bash`) are shared infrastructure used by all test files in Phases 2–4.

The `mock_cmd` function is particularly critical — it's the mechanism that lets us test `lib/check.sh` (which calls `claude`/`opencode`) and `lib/services.sh` (which calls `docker`) without requiring those tools to be installed.
