---
id: FEAT-testing-observability
title: "Test Observability — CI Summaries, Coverage, Documentation"
priority: P2
category: feature
status: open
depends_on:
  - ARCH-testing-ci-pipeline
estimated_effort: S
files_to_touch:
  - .github/workflows/ci.yml
  - tests/README.md
  - README.md
---

# Test Observability — CI Summaries, Coverage, Documentation

## Context

Phase 6 of the testing infrastructure buildout (parent: `ARCH-testing-infrastructure`). Depends on `ARCH-testing-ci-pipeline` (needs CI running before adding observability layers). This is P2 priority — a nice-to-have that improves developer experience but isn't blocking other work.

This task connects to `SPIKE-telemetry-observability`: that task observes agent behavior at runtime (Langfuse traces, session metrics), while this task provides build-time code health visibility (test results, coverage reports, testing conventions).

## Steps

1. **Add bats TAP output → GitHub Actions job summary**
   - Configure bats to output TAP format: `bats --tap tests/`
   - Parse TAP output into a markdown table for GitHub Actions step summary
   - Use `$GITHUB_STEP_SUMMARY` to display human-readable test results on the PR
   - Show: test name, pass/fail status, duration
   - Show total counts: passed, failed, skipped

2. **Evaluate Bash coverage tools**
   - Research `kcov` — C-based coverage tool that works with Bash scripts
   - Research `bashcov` — Ruby-based, uses SimpleCov under the hood
   - Evaluate: ease of install on macOS, accuracy with sourced files, CI integration
   - Pick one (or document why neither is viable for this project)
   - If viable: add `make coverage` target, generate HTML/JSON report

3. **Add coverage badge to README (if coverage tool is viable)**
   - Generate coverage report in CI
   - Upload to Codecov, Coveralls, or use a static badge
   - Add badge next to CI status badge in README.md

4. **Create `tests/README.md`** — testing conventions documentation
   - How to install bats-core locally (`brew install bats-core`)
   - How to run tests: `make test-unit`, `make test-integration`, `make test-e2e`, `make test-all`
   - How to run a single test file: `bats tests/unit/check.bats`
   - How to write a new test:
     - Which directory to put it in (unit vs integration vs e2e)
     - How to load helpers: `load '../helpers/common'`
     - How to use `mock_cmd` for external tools
     - How to use custom assertions
   - Mock strategy: explain PATH isolation, `mock_cmd`, `mock_cmd_with_args`
   - Fixture patterns: when to use fixtures vs inline test data
   - Naming conventions: `<library>.bats` for unit, `<flow>.bats` for integration/e2e
   - How to add a test to CI (it's automatic if in the right directory)

## Key Test Scenarios

| Feature | Expected |
|---------|----------|
| TAP output in CI | PR shows test summary table in Actions job summary |
| Coverage report | HTML report generated, shows % coverage per lib file |
| Coverage badge | README shows coverage percentage badge |
| tests/README.md | Documents all testing conventions accurately |

## Acceptance Criteria

- [ ] CI job summary shows human-readable test results on PRs
- [ ] Coverage tool evaluated and decision documented (viable or not)
- [ ] If coverage viable: `make coverage` target exists and generates report
- [ ] If coverage viable: coverage badge added to README.md
- [ ] `tests/README.md` exists and documents: running tests, writing tests, mock strategy, fixture patterns, naming conventions
- [ ] `tests/README.md` is accurate (matches actual test infrastructure)

## Verification

```bash
# Tests/README exists and is non-empty
test -s tests/README.md

# Coverage target (if implemented)
make coverage
open tests/coverage/index.html  # or equivalent

# CI verification: push to branch, check PR for:
# - Job summary with test results table
# - Coverage badge (if implemented)
```

## Workflow Integration

This task provides the "observability" layer for the testing infrastructure:

- **For developers**: `tests/README.md` is the reference for anyone working on testing tasks. When an agent picks up a testing task, it reads this file to understand conventions.
- **For CI**: TAP output summaries make test results visible without clicking into job logs. Developers can see at a glance which tests passed or failed on their PR.
- **For project health**: Coverage reports show which `lib/*.sh` functions have tests, highlighting gaps that need attention. This feeds back into task prioritization.
- **Connection to `SPIKE-telemetry-observability`**: That task observes agent behavior at runtime (Langfuse traces, session durations, tool usage). This task observes code health at build time (test pass rates, coverage percentages). Together they provide full-spectrum visibility into devflow quality.
