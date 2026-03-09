---
id: ARCH-testing-unit-tests
title: "Unit Tests for Core Libraries"
priority: P1
category: architecture
status: open
depends_on:
  - ARCH-testing-foundation
estimated_effort: L
files_to_touch:
  - tests/unit/check.bats
  - tests/unit/services.bats
  - tests/unit/skills.bats
  - tests/unit/init.bats
  - tests/fixtures/checks/
  - tests/fixtures/diff-samples/
  - tests/fixtures/skills/
---

# Unit Tests for Core Libraries

## Context

Phase 2 of the testing infrastructure buildout (parent: `ARCH-testing-infrastructure`). Depends on `ARCH-testing-foundation` for bats-core, helpers, and the `tests/` directory structure.

This is the largest testing task — it covers unit tests for the four highest-value library files. `lib/check.sh` is the top priority because it's the engine behind `devflow check`, the Code Review abstraction that `pre-push-check`, `create-pr`, and `finish-feature` skills all invoke. `lib/init.sh` is second priority because of the recently added symlink logic for `~/.claude/commands/devflow` and `~/.claude/skills/devflow-recall`.

## Steps

1. **Create `tests/unit/check.bats`** — test the multi-CLI code review abstraction
   - Test `_detect_review_cli` returns `claude` when `claude` is on PATH
   - Test `_detect_review_cli` returns `opencode` when only `opencode` is on PATH
   - Test `_detect_review_cli` respects `DEVFLOW_REVIEW_CLI` env var override
   - Test `_detect_review_cli` returns empty / fails when no CLI is available
   - Test `_collect_check_rules` concatenates all `.devflow/checks/*.md` files
   - Test `_collect_check_rules` returns empty for empty checks directory
   - Test `_collect_check_rules` handles missing `.devflow/checks/` directory gracefully
   - Test `_run_review_claude` passes rules as `--system-prompt` and diff via stdin
   - Test `_run_review_opencode` combines rules + diff into a single prompt
   - Test `devflow_check` dispatches to claude when detected
   - Test `devflow_check` falls back to opencode when claude is unavailable
   - Test `devflow_check` reports error when no CLI and no diff available

2. **Create `tests/unit/services.bats`** — test Layer 4 detection
   - Test `devflow_status` shows claude as detected when `claude` is on PATH
   - Test `devflow_status` shows opencode as detected when `opencode` is on PATH
   - Test `devflow_status` respects `DEVFLOW_REVIEW_CLI` env override
   - Test `devflow_status` shows "not found" when neither CLI is available
   - Test layer detection outputs (Docker, Hindsight, etc.) with appropriate mocks

3. **Create `tests/unit/skills.bats`** — test skills registry operations
   - Test `skills_list` outputs registered skills
   - Test `skills_install` creates expected files/directories
   - Test `skills_convert` generates valid plugin structure
   - Test edge cases: empty registry, missing skill files

4. **Create `tests/unit/init.bats`** — test project initialization
   - Test template copying creates `.devflow/checks/` directory with rule files
   - Test tool detection finds `claude` when available
   - Test tool detection finds `opencode` when available
   - Test tool detection does NOT detect `cn` (old Continue.dev CLI)
   - Test symlink creation for `~/.claude/commands/devflow` → plugin commands dir
   - Test symlink creation for `~/.claude/skills/devflow-recall` → recall skill dir
   - Test summary output includes correct paths and detected tools
   - Test init in a directory that already has `.devflow/` (idempotency)

5. **Create test fixtures**
   - `tests/fixtures/checks/code-quality.md` — sample check rule file
   - `tests/fixtures/checks/security.md` — sample check rule file
   - `tests/fixtures/diff-samples/simple.diff` — basic git diff with a few file changes
   - `tests/fixtures/diff-samples/multi-file.diff` — diff touching multiple files
   - `tests/fixtures/skills/sample-skill.md` — minimal skill file for registry tests
   - `tests/fixtures/project/` — minimal project directory with `.git/` and `CLAUDE.md`

6. **Verify all tests pass together**
   - Run `make test-unit` and confirm 40+ tests pass
   - Verify no test leaks state to another (run in random order if bats supports it)

## Key Test Scenarios

### lib/check.sh (highest priority)

| Test | Setup | Expected |
|------|-------|----------|
| detect claude | `mock_cmd claude` | `_detect_review_cli` outputs `claude` |
| detect opencode | remove claude mock, `mock_cmd opencode` | outputs `opencode` |
| env override | `DEVFLOW_REVIEW_CLI=opencode`, `mock_cmd claude` | outputs `opencode` |
| no CLI available | no mocks | returns non-zero or empty |
| collect rules (normal) | 2 files in `.devflow/checks/` | concatenated content |
| collect rules (empty dir) | empty `.devflow/checks/` | empty string |
| collect rules (no dir) | no `.devflow/checks/` | empty string, no error |
| run claude | mock claude, provide diff | `claude --print --system-prompt <rules>` called with diff on stdin |
| run opencode | mock opencode, provide diff | `opencode run` called with combined prompt |
| check dispatch | mock both CLIs | dispatches to detected CLI |
| check fallback | mock only opencode | falls back to opencode |
| check no CLI | no mocks | error message, non-zero exit |

### lib/init.sh

| Test | Setup | Expected |
|------|-------|----------|
| template copy | temp dir | `.devflow/checks/` created with rule files |
| detect claude | `mock_cmd claude` | summary shows claude detected |
| detect opencode | `mock_cmd opencode` | summary shows opencode detected |
| no cn detection | `mock_cmd cn` only | cn NOT listed as detected |
| symlink commands | temp HOME | `~/.claude/commands/devflow` symlink created |
| symlink skills | temp HOME | `~/.claude/skills/devflow-recall` symlink created |
| idempotent init | run init twice | no errors, no duplicate files |

## Acceptance Criteria

- [ ] `tests/unit/check.bats` has 12+ tests covering all `_detect_review_cli`, `_collect_check_rules`, `_run_review_*`, and `devflow_check` scenarios
- [ ] `tests/unit/services.bats` has 5+ tests covering Layer 4 CLI detection
- [ ] `tests/unit/skills.bats` has 4+ tests covering list/install/convert
- [ ] `tests/unit/init.bats` has 8+ tests covering template copy, tool detection, symlink creation
- [ ] Test fixtures exist for check rules, diffs, skills, and minimal project
- [ ] `make test-unit` runs 40+ total tests (including utils.bats from Phase 1), all pass
- [ ] No test calls real `claude`, `opencode`, `docker`, or any external tool
- [ ] Tests are independent — no test relies on state from a previous test

## Verification

```bash
# All unit tests pass
make test-unit

# Individual test files run cleanly
bats tests/unit/check.bats
bats tests/unit/services.bats
bats tests/unit/skills.bats
bats tests/unit/init.bats

# Test count check (should be 40+)
bats tests/unit/ 2>&1 | tail -1
```

## Workflow Integration

`lib/check.sh` is the highest priority test target — it's the engine behind `devflow check` which `pre-push-check`, `create-pr`, and `finish-feature` skills all invoke. Testing it means we can trust the Code Review pipeline that guards every PR.

`lib/init.sh` symlink tests validate the `make plugin-dev` dev workflow (from `ARCH-plugin-dev-workflow`). When `devflow init` creates symlinks for `~/.claude/commands/devflow` and `~/.claude/skills/devflow-recall`, these tests prove the symlinks point to the right targets.

`lib/services.sh` Layer 4 detection tests validate what `devflow status` reports — this is what developers see when they run `devflow status` to check their environment health.
