# Release Pipeline & Auto-Reinstall Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an automated release pipeline (GitHub Actions + conventional commits + Homebrew formula update) and an auto-reinstall extension to the existing watchdog that keeps the local devflow installation current.

**Architecture:** Two subsystems built sequentially on the same branch. The Release Pipeline adds `lib/release.sh` (conventional commit parser, semver arithmetic, version bump), `scripts/bump-version.sh` (standalone bumper), and `.github/workflows/release.yml` (CI). The Auto-Reinstall extends `lib/watch.sh` with SHA-based staleness detection and `make install`/`make link` invocation. Both build on the already-merged Sensitive File Watchdog.

**Tech Stack:** Bash (set -euo pipefail), GitHub Actions YAML, bats for tests, `gh` CLI for releases.

**Specs:**
- `docs/plans/2026-03-18-release-pipeline-design.md`
- `docs/plans/2026-03-18-auto-reinstall-design.md`

**Prerequisite:** The Sensitive File Watchdog is already merged to `main` (PR #19). This plan builds on `lib/watch.sh`, `check_version_consistency`, and the existing `Makefile` targets.

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `lib/release.sh` | CLI functions: `_parse_conventional_commits`, `_semver_bump`, `devflow_version_bump`, `devflow_release_preview` |
| `scripts/bump-version.sh` | Standalone version bump script (updates all 5+ version files via sed) |
| `.github/workflows/release.yml` | GitHub Actions workflow: auto-release on push to main |
| `tests/unit/release.bats` | Unit tests for conventional commit parsing, semver arithmetic, version bumping |

### Modified Files

| File | Changes |
|------|---------|
| `bin/devflow` | Add `source lib/release.sh`, dispatch `version-bump`, `release` commands, update help text |
| `lib/watch.sh` | Add `_detect_install_mode`, `_auto_reinstall_check`; call from `_watch_run`; add opt-in to `_watch_setup` |
| `tests/unit/watch.bats` | Add tests for install mode detection and auto-reinstall |
| `Makefile` | Add `version-bump` to `.PHONY` |
| `CLAUDE.md` | Document release process, conventional commits, auto-reinstall |

---

## Chunk 1: Conventional Commit Parser & Semver Arithmetic

### Task 1: Conventional Commit Parser

**Files:**
- Create: `lib/release.sh`
- Create: `tests/unit/release.bats`

- [ ] **Step 1: Create test file with conventional commit parser tests**

Create `tests/unit/release.bats`:

```bash
#!/usr/bin/env bats
# tests/unit/release.bats — Unit tests for lib/release.sh

setup() {
  load '../helpers/common'
  _common_setup
  load '../helpers/mocks'
  load '../helpers/assertions'
  source_lib utils.sh
  source_lib release.sh

  # Create a temp git repo for testing
  TEST_REPO="${BATS_TEST_TMPDIR}/test-repo"
  mkdir -p "$TEST_REPO"
  git -C "$TEST_REPO" init --quiet
  git -C "$TEST_REPO" config user.email "test@test.com"
  git -C "$TEST_REPO" config user.name "Test"
  # Initial commit
  echo "init" > "$TEST_REPO/file.txt"
  git -C "$TEST_REPO" add .
  git -C "$TEST_REPO" commit -m "chore: initial commit" --quiet
  git -C "$TEST_REPO" tag v0.1.0
}

teardown() {
  _common_teardown
}

# ── _parse_conventional_commits ────────────────────────────────

@test "parse_conventional_commits returns minor for feat: commits" {
  echo "feature" > "$TEST_REPO/feature.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "feat: add new feature" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "minor"
}

@test "parse_conventional_commits returns patch for fix: commits" {
  echo "fix" > "$TEST_REPO/fix.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "fix: resolve a bug" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "patch"
}

@test "parse_conventional_commits returns major for feat!: commits" {
  echo "breaking" > "$TEST_REPO/break.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "feat!: breaking API change" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "major"
}

@test "parse_conventional_commits returns major for BREAKING CHANGE footer" {
  echo "breaking2" > "$TEST_REPO/break2.txt"
  git -C "$TEST_REPO" add .
  git -C "$TEST_REPO" commit -m "feat: new api

BREAKING CHANGE: removes old endpoint" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "major"
}

@test "parse_conventional_commits returns none for only chore: commits" {
  echo "chore" > "$TEST_REPO/chore.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "chore: update deps" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "none"
}

@test "parse_conventional_commits returns none for [skip release]" {
  echo "feat" > "$TEST_REPO/feat.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "feat: add thing [skip release]" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "none"
}

@test "parse_conventional_commits picks highest bump (feat > fix)" {
  echo "fix" > "$TEST_REPO/fix.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "fix: bug fix" --quiet
  echo "feat" > "$TEST_REPO/feat.txt"
  git -C "$TEST_REPO" add . && git -C "$TEST_REPO" commit -m "feat: new feature" --quiet
  run _parse_conventional_commits "$TEST_REPO"
  assert_success
  assert_line --index 0 "minor"
}

@test "parse_conventional_commits handles first release (no previous tag)" {
  # Create a repo with no tags
  local fresh_repo="${BATS_TEST_TMPDIR}/fresh-repo"
  mkdir -p "$fresh_repo"
  git -C "$fresh_repo" init --quiet
  git -C "$fresh_repo" config user.email "test@test.com"
  git -C "$fresh_repo" config user.name "Test"
  echo "init" > "$fresh_repo/file.txt"
  git -C "$fresh_repo" add .
  git -C "$fresh_repo" commit -m "feat: initial feature" --quiet
  run _parse_conventional_commits "$fresh_repo"
  assert_success
  assert_line --index 0 "minor"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/release.bats`
Expected: FAIL — `source_lib release.sh` fails because file doesn't exist.

- [ ] **Step 3: Create lib/release.sh with conventional commit parser**

Create `lib/release.sh`:

```bash
#!/usr/bin/env bash
# devflow/lib/release.sh — Release pipeline functions
# Conventional commit parsing, semver arithmetic, version bumping.
# Sourced by bin/devflow.

# ── Conventional Commit Parser ───────────────────────────────────────────────

# _parse_conventional_commits [project_dir]
# Parses commits since last tag to determine version bump type.
# Output line 1: bump type (major/minor/patch/none)
# Output lines 2+: categorized commit messages (CATEGORY|message)
_parse_conventional_commits() {
  local project_dir="${1:-.}"

  # Get last tag
  local last_tag
  last_tag="$(git -C "$project_dir" describe --tags --abbrev=0 2>/dev/null || echo "")"

  # Determine commit range
  local range
  if [[ -n "$last_tag" ]]; then
    range="${last_tag}..HEAD"
  else
    # No previous tag — scan from initial commit
    local initial_commit
    initial_commit="$(git -C "$project_dir" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)"
    range="${initial_commit}..HEAD"
  fi

  # Get full commit messages (subject + body)
  local commits
  commits="$(git -C "$project_dir" log "$range" --format='%B---COMMIT_SEP---' 2>/dev/null || echo "")"
  if [[ -z "$commits" ]]; then
    echo "none"
    return 0
  fi

  # Check for [skip release] in the HEAD commit only (not the entire range)
  local head_msg
  head_msg="$(git -C "$project_dir" log -1 --format='%B' 2>/dev/null || echo "")"
  if echo "$head_msg" | grep -qi '\[skip release\]'; then
    echo "none"
    return 0
  fi

  local bump="none"
  local feat_msgs=""
  local fix_msgs=""
  local other_msgs=""

  # Parse each commit
  local IFS_SAVE="$IFS"
  while IFS= read -r -d '' commit_block; do
    [[ -z "$commit_block" ]] && continue
    local subject
    subject="$(echo "$commit_block" | head -1)"

    # Check for breaking changes (major)
    if [[ "$subject" == *"!"*":"* ]] || echo "$commit_block" | grep -q "^BREAKING CHANGE:"; then
      bump="major"
    fi

    # Categorize by prefix
    case "$subject" in
      feat:*|feat\(*)
        [[ "$bump" != "major" ]] && bump="minor"
        feat_msgs+="feat|${subject}\n"
        ;;
      fix:*|fix\(*)
        [[ "$bump" == "none" ]] && bump="patch"
        fix_msgs+="fix|${subject}\n"
        ;;
      docs:*|chore:*|refactor:*|test:*|ci:*|style:*|perf:*)
        other_msgs+="other|${subject}\n"
        ;;
    esac
  done < <(echo "$commits" | sed 's/---COMMIT_SEP---/\x00/g')
  IFS="$IFS_SAVE"

  # Output
  echo "$bump"
  [[ -n "$feat_msgs" ]] && printf "%b" "$feat_msgs"
  [[ -n "$fix_msgs" ]] && printf "%b" "$fix_msgs"
  [[ -n "$other_msgs" ]] && printf "%b" "$other_msgs"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/unit/release.bats`
Expected: All 8 parser tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/release.sh tests/unit/release.bats
git commit -m "feat(release): add conventional commit parser"
```

### Task 2: Semver Arithmetic

**Files:**
- Modify: `lib/release.sh`
- Test: `tests/unit/release.bats`

- [ ] **Step 1: Add semver tests**

Append to `tests/unit/release.bats`:

```bash
# ── _semver_bump ───────────────────────────────────────────────

@test "semver_bump minor: 0.1.0 → 0.2.0" {
  run _semver_bump "0.1.0" "minor"
  assert_success
  assert_output "0.2.0"
}

@test "semver_bump patch: 0.1.0 → 0.1.1" {
  run _semver_bump "0.1.0" "patch"
  assert_success
  assert_output "0.1.1"
}

@test "semver_bump major: 0.1.0 → 1.0.0" {
  run _semver_bump "0.1.0" "major"
  assert_success
  assert_output "1.0.0"
}

@test "semver_bump minor: 1.9.3 → 1.10.0" {
  run _semver_bump "1.9.3" "minor"
  assert_success
  assert_output "1.10.0"
}

@test "semver_bump returns error for none" {
  run _semver_bump "0.1.0" "none"
  assert_failure
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/unit/release.bats -f "semver_bump"`
Expected: FAIL — `_semver_bump` not defined.

- [ ] **Step 3: Implement semver arithmetic in lib/release.sh**

Append to `lib/release.sh`:

```bash
# ── Semver Arithmetic ────────────────────────────────────────────────────────

# _semver_bump <current_version> <bump_type>
# Returns the new version after applying the bump.
# Exit 1 if bump_type is "none".
_semver_bump() {
  local current="$1"
  local bump_type="$2"

  if [[ "$bump_type" == "none" ]]; then
    echo "No version bump needed" >&2
    return 1
  fi

  local major minor patch
  IFS='.' read -r major minor patch <<< "$current"

  case "$bump_type" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *)     echo "Unknown bump type: $bump_type" >&2; return 1 ;;
  esac
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/unit/release.bats -f "semver_bump"`
Expected: All 5 semver tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/release.sh tests/unit/release.bats
git commit -m "feat(release): add semver arithmetic"
```

---

## Chunk 2: Version Bump Script & CLI Wiring

### Task 3: Standalone Version Bump Script

**Files:**
- Create: `scripts/bump-version.sh`
- Test: `tests/unit/release.bats`

- [ ] **Step 1: Add version bump tests**

Append to `tests/unit/release.bats`:

```bash
# ── bump_all_versions (scripts/bump-version.sh) ───────────────

@test "bump_all_versions updates all version files" {
  local proj="${BATS_TEST_TMPDIR}/bump-project"
  mkdir -p "$proj/lib" "$proj/devflow-plugin/.claude-plugin" "$proj/devflow-plugin/commands"

  cat > "$proj/Makefile" <<'MF'
VERSION := 0.1.0
TARBALL := devflow-$(VERSION).tar.gz
MF
  cat > "$proj/lib/utils.sh" <<'US'
DEVFLOW_VERSION="0.1.0"
US
  cat > "$proj/devflow-plugin/.claude-plugin/plugin.json" <<'PJ'
{
  "name": "devflow",
  "version": "0.1.0"
}
PJ
  cat > "$proj/devflow-plugin/.claude-plugin/marketplace.json" <<'MJ'
{
  "version": "0.1.0"
}
MJ
  cat > "$proj/devflow-plugin/commands/test-cmd.md" <<'CMD'
---
description: "[devflow v0.1.0] Test command"
---
CMD

  run bump_all_versions "0.2.0" "$proj"
  assert_success

  # Verify each file was updated
  run grep 'VERSION := 0.2.0' "$proj/Makefile"
  assert_success
  run grep 'DEVFLOW_VERSION="0.2.0"' "$proj/lib/utils.sh"
  assert_success
  run grep '"version": "0.2.0"' "$proj/devflow-plugin/.claude-plugin/plugin.json"
  assert_success
  run grep '"version": "0.2.0"' "$proj/devflow-plugin/.claude-plugin/marketplace.json"
  assert_success
  run grep '\[devflow v0.2.0\]' "$proj/devflow-plugin/commands/test-cmd.md"
  assert_success
}

@test "bump_all_versions is idempotent" {
  local proj="${BATS_TEST_TMPDIR}/bump-idem"
  mkdir -p "$proj/lib" "$proj/devflow-plugin/.claude-plugin" "$proj/devflow-plugin/commands"
  cat > "$proj/Makefile" <<'MF'
VERSION := 0.2.0
MF
  cat > "$proj/lib/utils.sh" <<'US'
DEVFLOW_VERSION="0.2.0"
US
  cat > "$proj/devflow-plugin/.claude-plugin/plugin.json" <<'PJ'
{ "version": "0.2.0" }
PJ
  cat > "$proj/devflow-plugin/.claude-plugin/marketplace.json" <<'MJ'
{ "version": "0.2.0" }
MJ

  run bump_all_versions "0.2.0" "$proj"
  assert_success
  # Should not produce errors or change anything
  run grep 'VERSION := 0.2.0' "$proj/Makefile"
  assert_success
}

# ── formula update ─────────────────────────────────────────────

@test "formula_update_replaces_url_and_sha" {
  local proj="${BATS_TEST_TMPDIR}/formula-test"
  mkdir -p "$proj/Formula"
  cat > "$proj/Formula/devflow.rb" <<'FORMULA'
class Devflow < Formula
  url "https://github.com/AndreJorgeLopes/devflow/archive/refs/tags/v0.1.0.tar.gz"
  version "0.1.0"
  sha256 "PLACEHOLDER"
end
FORMULA
  local new_url="https://github.com/AndreJorgeLopes/devflow/releases/download/v0.2.0/devflow-0.2.0.tar.gz"
  local new_sha="abc123def456"
  sed "s|url \".*\"|url \"${new_url}\"|" "$proj/Formula/devflow.rb" > "$proj/Formula/devflow.rb.tmp" && mv "$proj/Formula/devflow.rb.tmp" "$proj/Formula/devflow.rb"
  sed "s|sha256 \".*\"|sha256 \"${new_sha}\"|" "$proj/Formula/devflow.rb" > "$proj/Formula/devflow.rb.tmp" && mv "$proj/Formula/devflow.rb.tmp" "$proj/Formula/devflow.rb"
  sed "s|version \".*\"|version \"0.2.0\"|" "$proj/Formula/devflow.rb" > "$proj/Formula/devflow.rb.tmp" && mv "$proj/Formula/devflow.rb.tmp" "$proj/Formula/devflow.rb"

  run grep 'url' "$proj/Formula/devflow.rb"
  assert_output --partial "releases/download/v0.2.0"
  run grep 'sha256' "$proj/Formula/devflow.rb"
  assert_output --partial "abc123def456"
  run grep 'version' "$proj/Formula/devflow.rb"
  assert_output --partial "0.2.0"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/unit/release.bats -f "bump_all_versions"`
Expected: FAIL — `bump_all_versions` not defined.

- [ ] **Step 3: Implement bump_all_versions in lib/release.sh and create the standalone script**

Append to `lib/release.sh`:

```bash
# ── Version Bump ─────────────────────────────────────────────────────────────

# bump_all_versions <new_version> [project_dir]
# Updates all version-bearing files to the new version using sed.
# This is the write-side counterpart to check_version_consistency (read-side).
bump_all_versions() {
  local new_version="$1"
  local proj="${2:-.}"

  # Portable sed -i wrapper (works on both macOS and GNU/Linux)
  _sed_inplace() {
    local pattern="$1" file="$2"
    sed "$pattern" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  }

  # Makefile: VERSION := X.Y.Z
  if [[ -f "$proj/Makefile" ]]; then
    _sed_inplace "s/^VERSION := .*/VERSION := ${new_version}/" "$proj/Makefile"
  fi

  # lib/utils.sh: DEVFLOW_VERSION="X.Y.Z"
  if [[ -f "$proj/lib/utils.sh" ]]; then
    _sed_inplace "s/DEVFLOW_VERSION=\"[^\"]*\"/DEVFLOW_VERSION=\"${new_version}\"/" "$proj/lib/utils.sh"
  fi

  # plugin.json: "version": "X.Y.Z"
  if [[ -f "$proj/devflow-plugin/.claude-plugin/plugin.json" ]]; then
    _sed_inplace "s/\"version\": \"[^\"]*\"/\"version\": \"${new_version}\"/" "$proj/devflow-plugin/.claude-plugin/plugin.json"
  fi

  # marketplace.json: "version": "X.Y.Z"
  if [[ -f "$proj/devflow-plugin/.claude-plugin/marketplace.json" ]]; then
    _sed_inplace "s/\"version\": \"[^\"]*\"/\"version\": \"${new_version}\"/" "$proj/devflow-plugin/.claude-plugin/marketplace.json"
  fi

  # Command description badges: [devflow vX.Y.Z]
  local cmd_file
  for cmd_file in "$proj"/devflow-plugin/commands/*.md; do
    [[ -f "$cmd_file" ]] || continue
    _sed_inplace "s/\[devflow v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\]/[devflow v${new_version}]/" "$cmd_file"
  done

  echo "All version files updated to ${new_version}"
}
```

Create `scripts/bump-version.sh`:

```bash
#!/usr/bin/env bash
# scripts/bump-version.sh — Standalone version bump script
# Usage: scripts/bump-version.sh <new_version> [project_dir]
# Updates all version-bearing files to the specified version.
# Used by both GitHub Actions and local CLI (devflow version-bump).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVFLOW_ROOT="$(dirname "$SCRIPT_DIR")"

source "${DEVFLOW_ROOT}/lib/utils.sh"
source "${DEVFLOW_ROOT}/lib/release.sh"

new_version="${1:?Usage: bump-version.sh <new_version> [project_dir]}"
project_dir="${2:-$DEVFLOW_ROOT}"

bump_all_versions "$new_version" "$project_dir"

# Validate consistency after bump
source "${DEVFLOW_ROOT}/lib/watch.sh"
check_version_consistency "$project_dir"
```

- [ ] **Step 4: Make the script executable**

```bash
chmod +x scripts/bump-version.sh
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/unit/release.bats -f "bump_all_versions"`
Expected: Both bump tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/release.sh scripts/bump-version.sh tests/unit/release.bats
git commit -m "feat(release): add version bump script for all version-bearing files"
```

### Task 4: CLI Wiring (version-bump + release preview)

**Files:**
- Modify: `lib/release.sh`
- Modify: `bin/devflow`
- Modify: `Makefile`

- [ ] **Step 1: Add CLI functions to lib/release.sh**

Append to `lib/release.sh`:

```bash
# ── CLI Commands ─────────────────────────────────────────────────────────────

# devflow_version_bump <new_version>
# CLI wrapper for bump_all_versions with validation.
devflow_version_bump() {
  local new_version="${1:?Usage: devflow version-bump <new_version>}"
  local proj
  proj="$(project_root)"

  section "Bumping version to ${new_version}"
  bump_all_versions "$new_version" "$proj"
  check_version_consistency "$proj" && ok "Version consistency validated"
}

# devflow_release_preview
# Shows what the next release would look like without creating it.
devflow_release_preview() {
  local proj
  proj="$(project_root)"

  section "Release Preview"

  # Current version
  local current_version
  current_version="$(grep '^VERSION' "$proj/Makefile" | head -1 | cut -d= -f2 | tr -d ' ')"
  info "Current version: v${current_version}"

  # Parse commits
  local parse_output
  parse_output="$(_parse_conventional_commits "$proj")"
  local bump_type
  bump_type="$(echo "$parse_output" | head -1)"

  if [[ "$bump_type" == "none" ]]; then
    info "No releasable commits since last tag. Nothing to release."
    return 0
  fi

  # Compute new version
  local new_version
  new_version="$(_semver_bump "$current_version" "$bump_type")"
  ok "Next version: v${new_version} (${bump_type} bump)"

  # Show categorized commits
  echo ""
  info "Commits to include:"
  echo "$parse_output" | tail -n +2 | while IFS='|' read -r category msg; do
    case "$category" in
      feat)  echo "  ${GREEN}feat${RESET}: $msg" ;;
      fix)   echo "  ${YELLOW}fix${RESET}: $msg" ;;
      other) echo "  ${DIM}$msg${RESET}" ;;
    esac
  done

  # Validate current version consistency
  echo ""
  if check_version_consistency "$proj" >/dev/null 2>&1; then
    ok "Version files are consistent"
  else
    fail "Version files are inconsistent — run 'devflow check-version' for details"
  fi
}
```

- [ ] **Step 2: Wire into bin/devflow**

Add `source "${DEVFLOW_ROOT}/lib/release.sh"` after the `source .../lib/watch.sh` line (after line 28).

Add dispatch cases in the `case` statement (after `check-version)`):

```bash
    version-bump)   devflow_version_bump "$@" ;;
    release)        devflow_release_preview "$@" ;;
```

Add to help text (after the `check-version` line):

```bash
  ${CYAN}version-bump${RESET} <version>     Bump version in all files
  ${CYAN}release${RESET}                    Preview next release (dry-run)
```

- [ ] **Step 3: Add version-bump to Makefile .PHONY**

Update the `.PHONY` line in `Makefile` to include `version-bump`:

```makefile
.PHONY: install uninstall link test test-unit brew-local release help plugin-dev plugin-unlink plugin-install check-version check-formula version-bump
```

Add a `version-bump` target:

```makefile
version-bump: ## Bump version (usage: make version-bump V=0.2.0)
	@if [ -z "$(V)" ]; then echo "Usage: make version-bump V=0.2.0"; exit 1; fi
	@bash scripts/bump-version.sh $(V)
```

- [ ] **Step 4: Run smoke test**

Run: `devflow release`
Expected: Shows current version, bump type, and categorized commits.

Run: `devflow help | grep -E "version-bump|release"`
Expected: Both commands appear in help output.

- [ ] **Step 5: Commit**

```bash
git add lib/release.sh bin/devflow Makefile
git commit -m "feat(release): add version-bump and release preview CLI commands"
```

---

## Chunk 3: GitHub Actions Workflow

### Task 5: Release Workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the workflow directory**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Create the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      bump_override:
        description: "Force bump type (major/minor/patch), or leave empty for auto-detect"
        required: false
      dry_run:
        description: "Preview what would happen without releasing"
        type: boolean
        default: false

permissions:
  contents: write

concurrency:
  group: release
  cancel-in-progress: false

jobs:
  release:
    runs-on: ubuntu-latest
    # Skip if this is a release bot commit
    if: "!startsWith(github.event.head_commit.message, 'chore(release):')"

    steps:
      - name: Checkout code (full history)
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Determine version bump
        id: bump
        run: |
          source lib/utils.sh
          source lib/release.sh

          # Get bump type from conventional commits
          PARSE_OUTPUT="$(_parse_conventional_commits .)"
          BUMP_TYPE="$(echo "$PARSE_OUTPUT" | head -1)"

          # Override from workflow_dispatch if provided
          if [[ -n "${{ inputs.bump_override }}" ]]; then
            BUMP_TYPE="${{ inputs.bump_override }}"
          fi

          if [[ "$BUMP_TYPE" == "none" ]]; then
            echo "No releasable commits. Skipping release."
            echo "skip=true" >> "$GITHUB_OUTPUT"
            exit 0
          fi

          # Get current version and compute new
          CURRENT="$(grep '^VERSION' Makefile | head -1 | cut -d= -f2 | tr -d ' ')"
          NEW_VERSION="$(_semver_bump "$CURRENT" "$BUMP_TYPE")"

          echo "bump_type=$BUMP_TYPE" >> "$GITHUB_OUTPUT"
          echo "current_version=$CURRENT" >> "$GITHUB_OUTPUT"
          echo "new_version=$NEW_VERSION" >> "$GITHUB_OUTPUT"
          echo "skip=false" >> "$GITHUB_OUTPUT"

          # Generate release notes body
          NOTES="## What's New"$'\n\n'
          FEATS="$(echo "$PARSE_OUTPUT" | grep '^feat|' | cut -d'|' -f2 || true)"
          FIXES="$(echo "$PARSE_OUTPUT" | grep '^fix|' | cut -d'|' -f2 || true)"
          OTHERS="$(echo "$PARSE_OUTPUT" | grep '^other|' | cut -d'|' -f2 || true)"

          if [[ -n "$FEATS" ]]; then
            NOTES+="### Features"$'\n'
            while IFS= read -r line; do NOTES+="- ${line}"$'\n'; done <<< "$FEATS"
            NOTES+=$'\n'
          fi
          if [[ -n "$FIXES" ]]; then
            NOTES+="### Fixes"$'\n'
            while IFS= read -r line; do NOTES+="- ${line}"$'\n'; done <<< "$FIXES"
            NOTES+=$'\n'
          fi
          if [[ -n "$OTHERS" ]]; then
            NOTES+="### Other Changes"$'\n'
            while IFS= read -r line; do NOTES+="- ${line}"$'\n'; done <<< "$OTHERS"
            NOTES+=$'\n'
          fi

          NOTES+="---"$'\n\n'
          NOTES+="## Install / Update"$'\n\n'
          NOTES+='**Quick install:**'$'\n'
          NOTES+='```bash'$'\n'
          NOTES+='curl -fsSL https://raw.githubusercontent.com/AndreJorgeLopes/devflow/main/install.sh | bash'$'\n'
          NOTES+='```'$'\n\n'
          NOTES+='**Homebrew:**'$'\n'
          NOTES+='```bash'$'\n'
          NOTES+='brew upgrade devflow'$'\n'
          NOTES+='```'$'\n\n'
          NOTES+='**From source:**'$'\n'
          NOTES+='```bash'$'\n'
          NOTES+='git pull && make install'$'\n'
          NOTES+='```'$'\n\n'
          NOTES+='**Then run:** `devflow init` to update hooks and config.'

          # Write notes to a file (multi-line output is tricky in GHA)
          echo "$NOTES" > /tmp/release-notes.md
          echo "Release: v${NEW_VERSION} (${BUMP_TYPE} bump from v${CURRENT})"

      - name: Exit if no release needed
        if: steps.bump.outputs.skip == 'true'
        run: echo "No release needed. Exiting."

      - name: Bump versions and build (dry-run check)
        if: steps.bump.outputs.skip != 'true' && inputs.dry_run == true
        run: |
          echo "DRY RUN — Would release v${{ steps.bump.outputs.new_version }}"
          echo "Bump type: ${{ steps.bump.outputs.bump_type }}"
          cat /tmp/release-notes.md

      - name: Bump versions, build, and release
        if: steps.bump.outputs.skip != 'true' && inputs.dry_run != true
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          NEW_VERSION: ${{ steps.bump.outputs.new_version }}
        run: |
          # 1. Bump all version files
          bash scripts/bump-version.sh "$NEW_VERSION"

          # 2. Create tarball
          make release

          # 3. Compute SHA256 and update Formula
          _sha256() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$1" | cut -d' ' -f1; }
          TARBALL="dist/devflow-${NEW_VERSION}.tar.gz"
          SHA="$(_sha256 "$TARBALL")"

          if [[ -f Formula/devflow.rb ]]; then
            RELEASE_URL="https://github.com/AndreJorgeLopes/devflow/releases/download/v${NEW_VERSION}/devflow-${NEW_VERSION}.tar.gz"
            sed -i "s|url \".*\"|url \"${RELEASE_URL}\"|" Formula/devflow.rb
            sed -i "s|sha256 \".*\"|sha256 \"${SHA}\"|" Formula/devflow.rb
            sed -i "s|version \".*\"|version \"${NEW_VERSION}\"|" Formula/devflow.rb
          fi

          # 4. Single commit + tag + push
          git add -A
          git commit -m "chore(release): v${NEW_VERSION} [skip release]"
          git tag "v${NEW_VERSION}"
          git push origin main --follow-tags

          # 5. Create GitHub Release with tarball asset
          gh release create "v${NEW_VERSION}" \
            --title "devflow v${NEW_VERSION}" \
            --notes-file /tmp/release-notes.md \
            "$TARBALL" \
            install.sh
```

- [ ] **Step 3: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "YAML valid"`
Expected: "YAML valid"

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci(release): add GitHub Actions release workflow"
```

---

## Chunk 4: Auto-Reinstall Watchdog Extension

### Task 6: Install Mode Detection

**Files:**
- Modify: `lib/watch.sh`
- Test: `tests/unit/watch.bats`

- [ ] **Step 1: Add install mode detection tests**

Append to `tests/unit/watch.bats`:

```bash
# ── _detect_install_mode ───────────────────────────────────────

@test "detect_install_mode returns link for symlinked devflow" {
  # Create a fake symlink
  ln -sf /some/repo/bin/devflow "${MOCK_DIR}/devflow"
  run _detect_install_mode
  assert_success
  assert_output "link"
}

@test "detect_install_mode returns install for regular file" {
  # Create a fake regular binary
  echo '#!/bin/bash' > "${MOCK_DIR}/devflow"
  chmod +x "${MOCK_DIR}/devflow"
  run _detect_install_mode
  assert_success
  assert_output "install"
}

@test "detect_install_mode returns brew for homebrew path" {
  # Create a fake symlink pointing to homebrew cellar
  mkdir -p "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin"
  echo '#!/bin/bash' > "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow"
  chmod +x "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow"
  ln -sf "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow" "${MOCK_DIR}/devflow"
  run _detect_install_mode
  assert_success
  assert_output "brew"
}

@test "detect_install_mode returns none when devflow not found" {
  # Remove any devflow from MOCK_DIR (ensure not in PATH)
  rm -f "${MOCK_DIR}/devflow"
  # Override PATH to only include MOCK_DIR (which has no devflow)
  PATH="${MOCK_DIR}" run _detect_install_mode
  assert_success
  assert_output "none"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/unit/watch.bats -f "detect_install_mode"`
Expected: FAIL — `_detect_install_mode` not defined.

- [ ] **Step 3: Implement _detect_install_mode in lib/watch.sh**

Add after the `_watch_notify` function (after line ~190 in `lib/watch.sh`), before the `# -- Watcher Core` section:

```bash
# ── Auto-Reinstall ───────────────────────────────────────────────────────────

# _detect_install_mode
# Detects how devflow is installed: link (symlink), install (copy), brew, or none.
_detect_install_mode() {
  local devflow_path
  devflow_path="$(command -v devflow 2>/dev/null || echo "")"
  [[ -z "$devflow_path" ]] && echo "none" && return

  # Resolve the real path for Homebrew detection
  local resolved_path
  resolved_path="$(readlink -f "$devflow_path" 2>/dev/null || readlink "$devflow_path" 2>/dev/null || echo "$devflow_path")"

  # Check for Homebrew paths
  if [[ "$resolved_path" == */opt/homebrew/* ]] || \
     [[ "$resolved_path" == */usr/local/Cellar/* ]] || \
     [[ "$resolved_path" == */home/linuxbrew/* ]] || \
     [[ "$resolved_path" == */Cellar/* ]]; then
    echo "brew"
    return
  fi

  # Check if it's a symlink (make link)
  if [[ -L "$devflow_path" ]]; then
    echo "link"
  else
    echo "install"
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/unit/watch.bats -f "detect_install_mode"`
Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/watch.sh tests/unit/watch.bats
git commit -m "feat(watch): add install mode detection (link/install/brew/none)"
```

### Task 7: Auto-Reinstall Check Function

**Files:**
- Modify: `lib/watch.sh`
- Test: `tests/unit/watch.bats`

- [ ] **Step 1: Add auto-reinstall tests**

Append to `tests/unit/watch.bats`:

```bash
# ── _auto_reinstall_check ─────────────────────────────────────

@test "auto_reinstall_check skips when not opted in" {
  # Create a .dev-setup without auto_reinstall
  local proj="${BATS_TEST_TMPDIR}/reinstall-test"
  mkdir -p "$proj/.devflow"
  echo "setup_at=2026-01-01" > "$proj/.devflow/.dev-setup"
  run _auto_reinstall_check "$proj" "" ""
  assert_success
  refute_output --partial "auto-updated"
}

@test "auto_reinstall_check skips when SHA matches" {
  local proj="${BATS_TEST_TMPDIR}/reinstall-match"
  mkdir -p "$proj/.devflow"
  echo "auto_reinstall=true" > "$proj/.devflow/.dev-setup"
  # Fake a matching SHA
  mkdir -p "${HOME}/.devflow"
  echo "abc1234" > "${HOME}/.devflow/.last-installed-sha"
  run _auto_reinstall_check "$proj" "abc1234" ""
  assert_success
  refute_output --partial "auto-updated"
  # Cleanup
  rm -f "${HOME}/.devflow/.last-installed-sha"
}

@test "auto_reinstall_check warns for brew install mode" {
  local proj="${BATS_TEST_TMPDIR}/reinstall-brew"
  mkdir -p "$proj/.devflow"
  echo "auto_reinstall=true" > "$proj/.devflow/.dev-setup"
  # Mock devflow as a brew-managed binary
  mkdir -p "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin"
  echo '#!/bin/bash' > "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow"
  chmod +x "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow"
  ln -sf "${BATS_TEST_TMPDIR}/opt/homebrew/Cellar/devflow/bin/devflow" "${MOCK_DIR}/devflow"
  run _auto_reinstall_check "$proj" "new-sha-123" ""
  assert_success
  assert_output --partial "Homebrew"
}

@test "auto_reinstall_check respects dry-run" {
  local proj="${BATS_TEST_TMPDIR}/reinstall-dryrun"
  mkdir -p "$proj/.devflow"
  echo "auto_reinstall=true" > "$proj/.devflow/.dev-setup"
  # Create a regular devflow mock (install mode)
  echo '#!/bin/bash' > "${MOCK_DIR}/devflow"
  chmod +x "${MOCK_DIR}/devflow"
  run _auto_reinstall_check "$proj" "new-sha-456" "" "1"
  assert_success
  assert_output --partial "DRY RUN"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/unit/watch.bats -f "auto_reinstall_check"`
Expected: FAIL — `_auto_reinstall_check` not defined.

- [ ] **Step 3: Implement _auto_reinstall_check in lib/watch.sh**

Add after `_detect_install_mode` in the `# -- Auto-Reinstall` section:

```bash
# _auto_reinstall_check <project_dir> <origin_sha> <headless> [dry_run]
# Checks if local devflow install is stale and updates it.
# Only runs if auto_reinstall=true in .devflow/.dev-setup.
_auto_reinstall_check() {
  local project_dir="$1"
  local origin_sha="$2"
  local headless="${3:-}"
  local dry_run="${4:-}"

  # Guard: check opt-in
  local setup_file="${project_dir}/.devflow/.dev-setup"
  if [[ ! -f "$setup_file" ]] || ! grep -q "auto_reinstall=true" "$setup_file" 2>/dev/null; then
    return 0
  fi

  # Compare installed SHA against origin/main SHA
  local sha_file="${HOME}/.devflow/.last-installed-sha"
  local last_installed_sha=""
  if [[ -f "$sha_file" ]]; then
    last_installed_sha="$(cat "$sha_file")"
  fi

  if [[ "$last_installed_sha" == "$origin_sha" ]]; then
    return 0  # Already up to date
  fi

  # Detect install mode
  local install_mode
  install_mode="$(_detect_install_mode)"

  local make_target=""
  case "$install_mode" in
    link)    make_target="link" ;;
    install) make_target="install" ;;
    brew)
      _watch_notify "devflow is managed by Homebrew. Run: brew upgrade devflow" "$headless"
      return 0
      ;;
    none)    return 0 ;;
  esac

  # Dry-run support
  local old_sha_short="${last_installed_sha:0:7}"
  local new_sha_short="${origin_sha:0:7}"

  if [[ -n "$dry_run" ]]; then
    echo "DRY RUN — Would run make ${make_target} (installed SHA: ${old_sha_short}, origin/main: ${new_sha_short})"
    return 0
  fi

  # Run make target, capture output for error logging
  local make_output
  if make_output="$(cd "$project_dir" && make "$make_target" 2>&1)"; then
    mkdir -p "${HOME}/.devflow"
    echo "$origin_sha" > "$sha_file"
    _watch_notify "devflow auto-updated ${old_sha_short}..${new_sha_short} (via make ${make_target})" "$headless"
  else
    # Log full make output for debugging
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] make ${make_target} FAILED output:" >> "${HOME}/.devflow/watch.log"
    echo "$make_output" >> "${HOME}/.devflow/watch.log"
    _watch_notify "devflow auto-update FAILED: make ${make_target} exited with code $?" "$headless"
    # Do NOT update SHA — next cron run will retry
  fi
}
```

- [ ] **Step 4: Wire into _watch_run**

In `_watch_run`, add a call to `_auto_reinstall_check` after the notification step (step 9) and before the fast-forward step (step 10). Find the line that says `# Step 10: Fast-forward local main` and insert before it:

```bash
  # Step 10: Auto-reinstall check
  _auto_reinstall_check "$project_dir" "$origin_sha" "$headless" "$dry_run"
```

Renumber the existing step 10 (fast-forward) to step 11 and step 11 (update SHA) to step 12.

- [ ] **Step 5: Add opt-in to _watch_setup**

In `_watch_setup`, after the "Store marker" section (after writing `.dev-setup`), add the auto-reinstall opt-in. Find the line `echo "project=${project_dir}" >> "${project_dir}/.devflow/.dev-setup"` and add after it:

```bash
  # 3b. Ask about auto-reinstall (only for devflow repo)
  if [[ -f "${project_dir}/lib/watch.sh" ]] && [[ -f "${project_dir}/bin/devflow" ]]; then
    echo ""
    info "This appears to be the devflow source repo."
    printf "Enable auto-reinstall? (Updates your local devflow when main gets new commits) [y/N] "
    read -r auto_reinstall_confirm
    if [[ "$auto_reinstall_confirm" == "y" ]] || [[ "$auto_reinstall_confirm" == "Y" ]]; then
      echo "auto_reinstall=true" >> "${project_dir}/.devflow/.dev-setup"
      ok "Auto-reinstall enabled"
    else
      skip "Auto-reinstall skipped"
    fi
  fi
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bats tests/unit/watch.bats`
Expected: All tests PASS (existing + new).

- [ ] **Step 7: Commit**

```bash
git add lib/watch.sh tests/unit/watch.bats
git commit -m "feat(watch): add auto-reinstall on merge detection with SHA-based staleness"
```

---

## Chunk 5: Documentation & Final Verification

### Task 8: CLAUDE.md & Documentation Updates

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add release process documentation to CLAUDE.md**

Add a new section after "Sensitive File Watchdog" (or after "Feature Lifecycle"):

```markdown
## Release Process

Releases are automated via GitHub Actions on push to main.

- **Conventional commits** determine the version bump:
  - `feat:` → minor, `fix:` → patch, `feat!:` / `BREAKING CHANGE:` → major
  - `[skip release]` in a commit message skips the release
- **Version files** are updated automatically by the workflow (Makefile, utils.sh, plugin.json, marketplace.json, all command badges)
- **GitHub Release** is created with tarball and install instructions
- **Homebrew formula** is updated with new SHA/URL in the same commit
- **Preview locally:** `devflow release` shows what the next release would be
- **Manual bump:** `devflow version-bump <version>` updates all files locally

### Auto-Reinstall

When `devflow watch setup` is run in the devflow source repo, it offers an auto-reinstall opt-in:
- Detects install mode: symlink (`make link`), copy (`make install`), or Homebrew
- On new commits to main, automatically runs the appropriate `make` target
- Homebrew installs get a notification to run `brew upgrade devflow` instead
- Uses SHA-based staleness detection (catches all changes, not just version bumps)
```

- [ ] **Step 2: Add lib/release.sh to CLAUDE.md project structure**

In the Project Structure tree, add after `watch.sh`:

```
  release.sh              # devflow release — version bump, release preview
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document release process, conventional commits, and auto-reinstall"
```

### Task 9: Final Verification

- [ ] **Step 1: Run all unit tests**

Run: `bats tests/unit/`
Expected: All tests pass (utils.bats + watch.bats + release.bats).

- [ ] **Step 2: Run smoke tests**

Run: `make test`
Expected: All smoke tests pass.

- [ ] **Step 3: Run check-version**

Run: `make check-version`
Expected: "All versions consistent: 0.1.0"

- [ ] **Step 4: Run release preview**

Run: `devflow release`
Expected: Shows current version, bump type, and categorized commits.

- [ ] **Step 5: Verify help includes all new commands**

Run: `devflow help`
Expected: `watch`, `check-version`, `version-bump`, `release` all appear.

- [ ] **Step 6: Validate workflow YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`
Expected: No errors.

- [ ] **Step 7: Run devflow finish-feature**

Invoke `/devflow:finish-feature` to run the full completion pipeline (verification, sensitive file check, PR creation, learnings retention).
