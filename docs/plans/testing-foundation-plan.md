# Testing Foundation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bootstrap the devflow testing infrastructure with bats-core, helper libraries, and the first unit test file for lib/utils.sh.

**Architecture:** All tests use bats-core with bats-support and bats-assert (installed via brew). Shared helpers provide PATH isolation, mock command generation, and custom assertions. Tests source lib/*.sh directly for unit testing. External commands are mocked via stub executables on PATH.

**Tech Stack:** bats-core, bats-support, bats-assert, GNU Make, Bash

**Task:** ARCH-testing-foundation (parent: ARCH-testing-infrastructure)

---

### Task 1: Install bats-core and companion libraries

**Files:**
- Modify: `~/Brewfile` (add testing tools)

**Step 1: Install bats packages via brew**

```bash
brew install bats-core bats-support bats-assert
```

**Step 2: Verify installation**

```bash
bats --version
ls "$(brew --prefix)/lib/bats-support/load.bash"
ls "$(brew --prefix)/lib/bats-assert/load.bash"
```

Expected: bats-core version printed, both load.bash files exist.

**Step 3: Add packages to ~/Brewfile**

In the `# Testing tools for devflow` section (after the devflow block):

```
# Testing (devflow)
brew "bats-core"
brew "bats-support"
brew "bats-assert"
```

---

### Task 2: Create tests/ directory structure

**Files:**
- Create: `tests/helpers/` (directory)
- Create: `tests/fixtures/` (directory)
- Create: `tests/unit/` (directory)
- Create: `tests/integration/` (directory)
- Create: `tests/e2e/` (directory)

**Step 1: Create all directories**

```bash
mkdir -p tests/{helpers,fixtures/diff-samples,unit,integration,e2e}
```

**Step 2: Verify structure exists**

```bash
ls tests/
```

Expected: `e2e  fixtures  helpers  integration  unit`

---

### Task 3: Create tests/helpers/common.bash

**Files:**
- Create: `tests/helpers/common.bash`

**Step 1: Write the helper file**

```bash
#!/usr/bin/env bash
# tests/helpers/common.bash — Shared setup/teardown for all bats tests

# Load bats helper libraries (installed via brew)
load "$(brew --prefix)/lib/bats-support/load"
load "$(brew --prefix)/lib/bats-assert/load"

# _common_setup — call from setup() in each test file
_common_setup() {
  # Determine devflow root (two levels up from tests/<category>/)
  DEVFLOW_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
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
```

Key points:
- `DEVFLOW_ROOT` derived from test file location (works for tests/unit/, tests/integration/, etc.)
- PATH isolation: mock dir is prepended so stubs shadow real commands
- `_ORIGINAL_PATH` saved for teardown restoration
- `source_lib` helper avoids hardcoded paths in test files

---

### Task 4: Create tests/helpers/mocks.bash

**Files:**
- Create: `tests/helpers/mocks.bash`

**Step 1: Write the mock helper file**

```bash
#!/usr/bin/env bash
# tests/helpers/mocks.bash — Mock command generators for test isolation

# mock_cmd <cmd> [exit_code] [stdout]
# Creates a stub executable that echoes stdout and exits with exit_code
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

# mock_cmd_with_args <cmd> [exit_code] [stdout]
# Like mock_cmd but records all arguments to a file for later assertion
mock_cmd_with_args() {
  local cmd="$1" exit_code="${2:-0}" stdout="${3:-}"
  local mock_dir="${BATS_TEST_TMPDIR}/mocks"
  mkdir -p "$mock_dir"
  cat > "${mock_dir}/${cmd}" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${BATS_TEST_TMPDIR}/${cmd}.args"
echo "${stdout}"
exit ${exit_code}
EOF
  chmod +x "${mock_dir}/${cmd}"
  export PATH="${mock_dir}:${PATH}"
}

# assert_mock_called_with <cmd> <expected_args>
# Checks that the mock was called with arguments containing the expected string
assert_mock_called_with() {
  local cmd="$1" expected="$2"
  local args_file="${BATS_TEST_TMPDIR}/${cmd}.args"
  assert [ -f "$args_file" ]
  run grep -F "$expected" "$args_file"
  assert_success
}
```

Key points:
- `mock_cmd` is the simple version — ignores arguments, returns fixed output
- `mock_cmd_with_args` records `$@` to a file for later verification
- Both prepend mock dir to PATH (idempotent, harmless if called multiple times)
- `\$@` in heredoc becomes `$@` in the generated script (captures call-time args)

---

### Task 5: Create tests/helpers/assertions.bash

**Files:**
- Create: `tests/helpers/assertions.bash`

**Step 1: Write the assertion helper file**

```bash
#!/usr/bin/env bash
# tests/helpers/assertions.bash — Custom assertion helpers

# assert_line_contains <line_number> <substring>
# Check that a specific line in $output contains a substring
assert_line_contains() {
  local line_num="$1" substring="$2"
  local line="${lines[$line_num]}"
  if [[ "$line" != *"$substring"* ]]; then
    echo "Expected line $line_num to contain '$substring'" >&2
    echo "Actual: '$line'" >&2
    return 1
  fi
}

# assert_file_exists <path>
assert_file_exists() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "Expected file to exist: $path" >&2
    return 1
  fi
}

# assert_file_contains <path> <string>
assert_file_contains() {
  local path="$1" string="$2"
  if ! grep -qF "$string" "$path" 2>/dev/null; then
    echo "Expected file '$path' to contain '$string'" >&2
    return 1
  fi
}

# assert_symlink_to <path> <target>
assert_symlink_to() {
  local path="$1" target="$2"
  if [[ ! -L "$path" ]]; then
    echo "Expected '$path' to be a symlink" >&2
    return 1
  fi
  local actual_target
  actual_target="$(readlink "$path")"
  if [[ "$actual_target" != "$target" ]]; then
    echo "Expected symlink '$path' -> '$target'" >&2
    echo "Actual target: '$actual_target'" >&2
    return 1
  fi
}
```

---

### Task 6: Write tests/unit/utils.bats

**Files:**
- Create: `tests/unit/utils.bats`
- Reference: `lib/utils.sh` (functions under test)

**Step 1: Write the test file (9 tests)**

```bash
#!/usr/bin/env bats
# tests/unit/utils.bats — Unit tests for lib/utils.sh

setup() {
  load '../helpers/common'
  _common_setup
  load '../helpers/mocks'
  load '../helpers/assertions'
  source_lib utils.sh
}

teardown() {
  _common_teardown
}

# ── has_cmd ───────────────────────────────────────────────────────

@test "has_cmd returns 0 for an available command (bash)" {
  run has_cmd bash
  assert_success
}

@test "has_cmd returns 1 for a nonexistent command" {
  run has_cmd nonexistent_xyz_12345
  assert_failure
}

# ── project_root ──────────────────────────────────────────────────

@test "project_root returns directory containing .git" {
  run project_root
  assert_success
  assert [ -d "${output}/.git" ]
}

# ── devflow_root ──────────────────────────────────────────────────

@test "DEVFLOW_ROOT points to valid devflow installation" {
  assert [ -d "$DEVFLOW_ROOT" ]
  assert [ -x "$DEVFLOW_ROOT/bin/devflow" ]
  assert [ -f "$DEVFLOW_ROOT/lib/utils.sh" ]
}

# ── detect_vcs_provider ──────────────────────────────────────────

@test "detect_vcs_provider returns github for github.com remote" {
  mock_cmd git 0 "git@github.com:user/repo.git"
  run detect_vcs_provider
  assert_output "github"
}

@test "detect_vcs_provider returns gitlab for gitlab.com remote" {
  mock_cmd git 0 "git@gitlab.com:user/repo.git"
  run detect_vcs_provider
  assert_output "gitlab"
}

@test "detect_vcs_provider returns unknown with no git remote" {
  mock_cmd git 1 ""
  run detect_vcs_provider
  assert_output "unknown"
}

# ── get_vcs_pr_term ───────────────────────────────────────────────

@test "get_vcs_pr_term returns PR for github provider" {
  mock_cmd git 0 "git@github.com:user/repo.git"
  run get_vcs_pr_term
  assert_output "PR"
}

@test "get_vcs_pr_term returns MR for gitlab provider" {
  mock_cmd git 0 "git@gitlab.com:user/repo.git"
  run get_vcs_pr_term
  assert_output "MR"
}
```

Design notes:
- VCS tests mock `git` because `detect_vcs_provider` calls `git remote get-url origin` internally
- `get_vcs_pr_term` also calls `detect_vcs_provider` internally (no argument), so we mock `git` the same way
- `project_root` test uses real git (we're in a real repo)
- `devflow_root` test validates the env var set by common.bash (BASH_SOURCE resolution is context-dependent)

**Step 2: Run the tests**

```bash
bats tests/unit/utils.bats
```

Expected: 9 tests, 9 passed.

---

### Task 7: Update Makefile

**Files:**
- Modify: `Makefile:7` (.PHONY line)
- Modify: `Makefile` (add target after existing `test:` block)

**Step 1: Add test-unit to .PHONY and add target**

Add `test-unit` to the `.PHONY` line and add the target after the existing `test:` block:

```makefile
test-unit: ## Run unit tests (bats)
	@bats tests/unit/
```

**Step 2: Verify**

```bash
make test-unit
```

Expected: 9 tests pass.

---

### Task 8: Create minimal fixtures

**Files:**
- Create: `tests/fixtures/diff-samples/simple.diff`
- Create: `tests/fixtures/.gitkeep`
- Create: `tests/integration/.gitkeep`
- Create: `tests/e2e/.gitkeep`

**Step 1: Create .gitkeep files for empty directories**

```bash
touch tests/fixtures/.gitkeep tests/integration/.gitkeep tests/e2e/.gitkeep
```

**Step 2: Create a sample diff fixture**

```diff
diff --git a/example.txt b/example.txt
index 1234567..abcdefg 100644
--- a/example.txt
+++ b/example.txt
@@ -1,3 +1,4 @@
 line one
 line two
+line three
 line four
```

---

### Task 9: Verify everything

**Step 1: Check framework**

```bash
bats --version
```

**Step 2: Check directory structure**

```bash
ls tests/helpers/ tests/fixtures/ tests/unit/ tests/integration/ tests/e2e/
```

**Step 3: Run all unit tests**

```bash
make test-unit
```

Expected: 9 tests, 9 passed, exit 0.

**Step 4: Run specific test file**

```bash
bats tests/unit/utils.bats
```

Expected: same 9 tests pass.
