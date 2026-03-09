---
id: ARCH-testing-infrastructure
title: "End-to-End Testing Infrastructure and CI Pipeline"
priority: P1
category: architecture
status: open
depends_on: []
estimated_effort: XL
files_to_touch:
  - Makefile
  - tests/unit/*.bats
  - tests/integration/*.bats
  - tests/e2e/*.bats
  - tests/helpers/*.bash
  - tests/fixtures/
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - lib/utils.sh
  - lib/check.sh
  - lib/init.sh
  - lib/services.sh
  - lib/skills.sh
  - lib/seed.sh
  - lib/worktree.sh
  - lib/visualizations.sh
  - bin/devflow
  - README.md
---

# End-to-End Testing Infrastructure and CI Pipeline

## Context

Devflow is a Bash CLI orchestrating 6 layers of AI dev tooling across 8 library files, 13 skills, a plugin system, and 28 open tasks. Currently, the only testing is 3 smoke tests in the Makefile (`bin/devflow` exists, version matches, help produces output). There are:

- **No unit tests** for any `lib/*.sh` function
- **No integration tests** for CLI commands (`devflow init`, `devflow check`, `devflow status`, etc.)
- **No end-to-end tests** for multi-step workflows (init → check → status pipeline)
- **No CI pipeline** (no GitHub Actions, no automated testing on push/PR)
- **No test framework** installed (no bats-core, no shunit2)
- **No test fixtures** or mock infrastructure for external dependencies (Docker, claude, opencode, agent-deck, wt, Hindsight API)

Every task file has a `## Verification` section with manual bash commands, but none are automated. As the codebase grows (28 tasks pending), we need confidence that changes don't break existing functionality — especially after large refactors like the recent Continue.dev → Code Review migration that touched 22+ files.

## Problem Statement

1. **Regression risk**: Large refactors (like the Code Review migration) touch 22+ files with no automated verification beyond manual grep.
2. **Contributor friction**: New contributors have no way to verify their changes work before pushing.
3. **Slow feedback**: Manual verification after each change is tedious and error-prone.
4. **No observability into test health**: No dashboard, no CI badges, no history of what passed/failed.
5. **False confidence**: The existing 3 smoke tests create an illusion of test coverage.

## Goals

1. **Test framework**: Install and configure bats-core (Bash Automated Testing System) — the de facto standard for Bash testing.
2. **Unit tests**: Test individual functions in `lib/*.sh` in isolation (with mocked external commands).
3. **Integration tests**: Test CLI commands end-to-end with controlled fixtures.
4. **E2E workflow tests**: Test multi-step flows (init → check → status) in isolated environments.
5. **CI pipeline**: GitHub Actions workflow that runs tests on every push and PR.
6. **Test observability**: CI badges in README, test result summaries, failure notifications.
7. **Mock infrastructure**: Helper functions to mock external CLIs (docker, claude, opencode, wt, agent-deck) for deterministic tests.

## Architecture

### Test Framework: bats-core

```
tests/
├── helpers/
│   ├── common.bash          # Shared setup/teardown, temp dirs, PATH isolation
│   ├── mocks.bash           # Mock command generators (mock_cmd claude, mock_cmd docker, etc.)
│   └── assertions.bash      # Custom assertions (assert_line_contains, assert_file_exists, etc.)
├── fixtures/
│   ├── project/             # Fake project directory for init/check tests
│   │   ├── .devflow/checks/ # Pre-populated check rules
│   │   ├── .git/            # Minimal git repo
│   │   └── CLAUDE.md        # Minimal config
│   ├── diff-samples/        # Sample git diffs for check tests
│   └── skills/              # Minimal skill files for registry tests
├── unit/
│   ├── utils.bats           # Tests for lib/utils.sh functions
│   ├── check.bats           # Tests for lib/check.sh functions
│   ├── init.bats            # Tests for lib/init.sh functions
│   ├── services.bats        # Tests for lib/services.sh functions
│   ├── skills.bats          # Tests for lib/skills.sh functions
│   ├── seed.bats            # Tests for lib/seed.sh functions
│   ├── worktree.bats        # Tests for lib/worktree.sh functions
│   └── visualizations.bats  # Tests for lib/visualizations.sh functions
├── integration/
│   ├── cli-commands.bats    # Test all devflow subcommands (help, version, status, etc.)
│   ├── init-flow.bats       # Test devflow init end-to-end (with mocked tools)
│   ├── check-flow.bats      # Test devflow check end-to-end (with mocked claude/opencode)
│   └── skills-flow.bats     # Test devflow skills list/install/convert
└── e2e/
    ├── full-workflow.bats    # Init → check → status → review pipeline
    └── plugin-lifecycle.bats # Skills convert → validate → install
```

### Mocking Strategy

External CLIs are mocked by creating stub executables in a temp `$PATH`:

```bash
# helpers/mocks.bash
mock_cmd() {
  local cmd="$1" exit_code="${2:-0}" stdout="${3:-}"
  local mock_dir="${BATS_TEST_TMPDIR}/mocks"
  mkdir -p "$mock_dir"
  cat > "${mock_dir}/${cmd}" <<EOF
#!/usr/bin/env bash
echo "${stdout}"
exit ${exit_code}
EOF
  chmod +x "${mock_dir}/${cmd}"
  export PATH="${mock_dir}:${PATH}"
}
```

Mock targets:
- `claude` — mock `--print` output (structured JSON for check tests)
- `opencode` — mock `run` output (text for check fallback tests)
- `docker` — mock `info`, `compose` for service tests
- `wt` — mock worktree operations
- `agent-deck` — mock session/conductor/group operations
- `git` — selective mocking for diff/log output (or use real repos in fixtures)
- `brew` — mock install operations
- `uvx` — mock Hindsight operations

### CI Pipeline

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest  # devflow targets macOS
    steps:
      - uses: actions/checkout@v4
      - name: Install bats-core
        run: brew install bats-core
      - name: Run unit tests
        run: make test-unit
      - name: Run integration tests
        run: make test-integration
      - name: Run e2e tests
        run: make test-e2e
      - name: Verify plugin
        run: |
          npm install -g @anthropic-ai/claude-code
          claude plugin validate devflow-plugin

  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run ShellCheck
        uses: ludeeus/action-shellcheck@master
        with:
          scandir: './lib'
```

### Makefile Targets

```makefile
test-unit:        ## Run unit tests
test-integration: ## Run integration tests
test-e2e:         ## Run end-to-end tests
test-all:         ## Run all tests (unit + integration + e2e)
test:             ## Alias for test-all (replaces current smoke tests)
lint:             ## Run ShellCheck on lib/*.sh
coverage:         ## Generate test coverage report (via kcov or similar)
```

## Implementation Phases

### Phase 1: Foundation (S effort)
1. Install bats-core (`brew install bats-core`)
2. Create `tests/` directory structure
3. Create `tests/helpers/common.bash` with setup/teardown
4. Create `tests/helpers/mocks.bash` with `mock_cmd` function
5. Write first test: `tests/unit/utils.bats` — test `has_cmd`, `project_root`, `devflow_root`
6. Update Makefile with `test-unit` target
7. Verify: `make test-unit` passes

### Phase 2: Unit Tests for Core Libraries (L effort)
1. `tests/unit/check.bats` — test `_detect_review_cli`, `_collect_check_rules`, `_run_review_claude`, `_run_review_opencode`, `devflow_check`
2. `tests/unit/services.bats` — test `devflow_status` layer detection
3. `tests/unit/skills.bats` — test `skills_list`, `skills_install`, `skills_convert`
4. `tests/unit/init.bats` — test template copying, tool detection
5. Create test fixtures: sample `.devflow/checks/` rules, sample diffs, minimal git repos
6. Verify: `make test-unit` passes with all new tests

### Phase 3: Integration Tests (M effort)
1. `tests/integration/cli-commands.bats` — every devflow subcommand returns success
2. `tests/integration/check-flow.bats` — devflow check with mocked claude/opencode
3. `tests/integration/init-flow.bats` — devflow init in a temp directory
4. `tests/integration/skills-flow.bats` — list/install/convert/validate cycle
5. Add `test-integration` Makefile target
6. Verify: `make test-integration` passes

### Phase 4: E2E Tests (M effort)
1. `tests/e2e/full-workflow.bats` — init → check → status → review
2. `tests/e2e/plugin-lifecycle.bats` — convert → validate
3. Add `test-e2e` Makefile target
4. Verify: `make test-e2e` passes

### Phase 5: CI Pipeline (S effort)
1. Create `.github/workflows/ci.yml`
2. Add ShellCheck linting step
3. Add test badge to README.md
4. Verify: push to branch, CI runs green

### Phase 6: Observability and Coverage (S effort)
1. Add test result summary in CI (bats TAP output → GitHub summary)
2. Consider kcov or bashcov for coverage reporting
3. Add CI status badge to README
4. Document testing conventions in a `tests/README.md`

## Key Test Scenarios

### lib/check.sh (highest priority — new code)
- `_detect_review_cli` returns `claude` when claude is on PATH
- `_detect_review_cli` returns `opencode` when only opencode is on PATH
- `_detect_review_cli` respects `DEVFLOW_REVIEW_CLI` env override
- `_detect_review_cli` fails gracefully when no CLI available
- `_collect_check_rules` concatenates all `.devflow/checks/*.md` files
- `_collect_check_rules` handles empty directory
- `_collect_check_rules` handles missing directory
- `_run_review_claude` passes rules as --system-prompt and diff as stdin
- `_run_review_opencode` combines rules + diff into single prompt
- `devflow_check` dispatches to correct CLI based on detection
- `devflow_check` falls back from claude to opencode
- `devflow_check` reports error when no diff and no CLI

### lib/services.sh
- `devflow_status` shows correct Layer 4 status for each CLI combination
- `devflow_up` checks for required CLI tools
- `devflow_down` message includes updated tool names

### lib/init.sh
- Template copying uses `.devflow/checks/` (not `.continue/checks/`)
- Tool detection finds claude/opencode (not cn)
- Summary output shows correct paths

### bin/devflow
- All subcommands dispatch correctly
- Help text mentions Code Review (not Continue.dev)
- Unknown commands produce error

### Skills
- `devflow skills list` shows all registered skills including dependency-update
- `devflow skills convert` generates valid plugin
- Plugin validates with `claude plugin validate`

## Acceptance Criteria

- [ ] `make test-unit` runs 40+ unit tests, all pass
- [ ] `make test-integration` runs 15+ integration tests, all pass
- [ ] `make test-e2e` runs 5+ e2e tests, all pass
- [ ] `make lint` runs ShellCheck with zero errors on lib/*.sh
- [ ] `.github/workflows/ci.yml` runs on push and PR
- [ ] CI badge in README shows passing status
- [ ] No test requires real Docker, Hindsight, claude, or opencode (all mocked)
- [ ] Tests run in <30 seconds total on macOS
- [ ] Test helpers (mocks, fixtures) are documented in tests/README.md

## Verification

```bash
# Framework installed
bats --version

# All tests pass
make test-all

# Lint clean
make lint

# CI config valid
act -n  # dry-run GitHub Actions locally (if act is installed)

# Plugin still validates after test infrastructure changes
claude plugin validate devflow-plugin
```

## Related Tasks

- `SPIKE-telemetry-observability` — Complementary: that task observes agent behavior at runtime, this task verifies devflow code correctness at build time
- `FEAT-langfuse-traces-tldr` — The Langfuse traces skill should be testable with mocked Langfuse API responses
- `ARCH-session-task-completion` — The `done.md` skill's verification step could invoke `make test` as part of its pipeline

## Technical Notes

- **bats-core** is the standard: used by Homebrew, Docker, and other major Bash projects. Install: `brew install bats-core`.
- **bats-support** and **bats-assert** are companion libraries for richer assertions.
- Tests should source `lib/*.sh` directly (not go through `bin/devflow`) for unit testing.
- Integration tests should invoke `bin/devflow` as a subprocess.
- Mock PATH isolation ensures tests never call real external tools.
- Consider `bats-file` for filesystem assertions (file exists, contains, permissions).
- ShellCheck (already available via brew) catches common Bash pitfalls statically.
- For CI, `macos-latest` runner is preferred since devflow targets macOS. Add `ubuntu-latest` as secondary to catch portability issues.
