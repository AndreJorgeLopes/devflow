---
id: ARCH-testing-e2e
title: "End-to-End Tests — Full Workflow Pipelines"
priority: P1
category: architecture
status: open
depends_on:
  - ARCH-testing-integration
estimated_effort: M
files_to_touch:
  - Makefile
  - tests/e2e/full-workflow.bats
  - tests/e2e/plugin-lifecycle.bats
---

# End-to-End Tests — Full Workflow Pipelines

## Context

Phase 4 of the testing infrastructure buildout (parent: `ARCH-testing-infrastructure`). Depends on `ARCH-testing-integration` (integration tests prove individual commands work; E2E tests chain them into realistic workflows).

E2E tests exercise multi-step pipelines in fully isolated temporary projects. They mirror the actual devflow development flow: `devflow init` sets up a project → `devflow check` reviews code → `devflow status` reports health. This is exactly what `finish-feature` does before creating a PR.

This phase also consolidates the Makefile test targets: `test-all` runs unit + integration + e2e, and `make test` is updated to point to `test-all` (replacing the current 3 smoke tests).

## Steps

1. **Create `tests/e2e/full-workflow.bats`** — init → check → status pipeline
   - Set up a completely isolated temp directory with a git repo
   - Run `devflow init` — verify `.devflow/checks/` created, symlinks set up
   - Create a dummy file, `git add`, `git commit`
   - Make a change and stage it (`git add`)
   - Run `devflow check` (with mocked claude) — verify review output
   - Run `devflow status` — verify all layers report correctly
   - Verify the entire pipeline exits cleanly with no orphaned temp files
   - Test the pipeline with opencode fallback (no claude mock)

2. **Create `tests/e2e/plugin-lifecycle.bats`** — skills convert → validate → install
   - Run `devflow skills convert` — verify plugin structure is generated
   - Verify generated `devflow-plugin/` has expected files (package.json, commands/, etc.)
   - Mock `claude plugin validate` — verify it would be called with correct args
   - Mock symlink install (`make plugin-dev` equivalent) — verify symlinks created
   - Verify commands are discoverable at the expected symlink paths
   - Clean up: verify no artifacts left outside temp dirs

3. **Add Makefile targets**
   - `test-e2e`: `bats tests/e2e/`
   - `test-all`: runs `test-unit`, `test-integration`, `test-e2e` sequentially
   - Update `test` target: replace current smoke tests with `test-all`
   - Preserve old smoke tests as comments or in a `test-smoke` target for reference

4. **Verify full test suite**
   - `make test-all` runs unit + integration + e2e
   - `make test` is now an alias for `test-all`
   - Total test count across all suites: 60+

## Key Test Scenarios

### Full Workflow Pipeline

| Step | Command | Assertions |
|------|---------|------------|
| 1. Init project | `devflow init` | `.devflow/checks/` exists, symlinks created |
| 2. Create commit | `git add && git commit` | clean working tree |
| 3. Stage changes | `echo change >> file && git add` | staged diff exists |
| 4. Run check | `devflow check` | mocked claude called with rules + diff, exits 0 |
| 5. Check status | `devflow status` | Layer 4 shows claude detected, exits 0 |
| 6. Cleanup | (automatic) | no temp files leaked |

### Plugin Lifecycle

| Step | Command | Assertions |
|------|---------|------------|
| 1. Convert skills | `devflow skills convert` | `devflow-plugin/` directory created |
| 2. Validate structure | check files | package.json, commands/*.md exist |
| 3. Validate plugin | mock `claude plugin validate` | called with correct plugin path |
| 4. Install via symlink | mock `make plugin-dev` | symlinks at expected HOME paths |
| 5. Verify discovery | check symlink targets | commands point to plugin commands dir |

### Edge Cases

| Scenario | Expected |
|----------|----------|
| Init in non-git directory | appropriate error or creates .git |
| Check with no rules dir | graceful fallback, still runs |
| Status with no tools installed | all layers show "not found" |
| Full pipeline, opencode only | fallback works, pipeline completes |

## Acceptance Criteria

- [ ] `tests/e2e/full-workflow.bats` has 5+ tests covering init → check → status pipeline
- [ ] `tests/e2e/plugin-lifecycle.bats` has 3+ tests covering convert → validate → install
- [ ] `make test-e2e` runs all E2E tests and passes
- [ ] `make test-all` runs unit + integration + e2e sequentially, all pass
- [ ] `make test` is now aliased to `test-all` (replaces old 3 smoke tests)
- [ ] Total test count across all suites is 60+
- [ ] E2E tests run in fully isolated temp directories (no side effects)
- [ ] E2E tests clean up after themselves (no leaked temp dirs or symlinks)

## Verification

```bash
# E2E tests pass
make test-e2e

# Individual E2E test files
bats tests/e2e/full-workflow.bats
bats tests/e2e/plugin-lifecycle.bats

# Full test suite
make test-all

# Alias works
make test

# Test count check (should be 60+ total)
make test-all 2>&1 | grep -E "^[0-9]+ tests"
```

## Workflow Integration

These tests mirror the actual devflow development flow that `finish-feature` orchestrates:

1. Developer runs `devflow init` (tested in init step)
2. Developer writes code, stages changes
3. `finish-feature` runs `devflow check` to review (tested in check step)
4. `finish-feature` runs `devflow status` to verify environment (tested in status step)
5. If all pass, `finish-feature` creates a PR

By automating this pipeline in E2E tests, we catch workflow-level regressions that unit or integration tests would miss — like `devflow init` creating a config that `devflow check` can't read, or `devflow status` reporting a false positive after `devflow init` runs.

The Makefile consolidation (`make test` → `make test-all`) means that `done.md` (ARCH-session-task-completion) and `pre-push-check` skills can invoke a single `make test` command and get comprehensive coverage instead of the current 3 smoke tests.
