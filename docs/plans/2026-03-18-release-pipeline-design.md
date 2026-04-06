# Release Pipeline

**Date:** 2026-03-18
**Status:** Draft
**Scope:** Automated versioning, GitHub Releases, and Homebrew formula updates
**Depends on:** Sensitive File Watchdog (`lib/watch.sh`, `.devflow/sensitive-files.conf`) for version-bearing file list

## Problem

Devflow's version is hardcoded in 5+ places (Makefile, lib/utils.sh, plugin.json, marketplace.json, all command description badges). There is no release automation — no GitHub Actions, no `gh release`, no changelog generation. The `make release` target only creates a tarball and prints a SHA for manual Homebrew formula update. Releasing a new version requires manually editing all version files, creating a tarball, uploading it, and updating the formula.

## Solution

A GitHub Actions workflow that triggers on every push to `main`, parses conventional commits to determine the version bump, updates all version-bearing files, creates a GitHub Release with install instructions and tarball, and updates the Homebrew formula — all automatically in a single atomic operation.

## Architecture

### Trigger

Push to `main` branch. The workflow runs on every merge/push to main.

**Re-trigger prevention:** The workflow's own commits use `chore(release):` prefix. The `on.push` trigger includes a filter:

```yaml
on:
  push:
    branches: [main]

# In the job:
jobs:
  release:
    if: "!startsWith(github.event.head_commit.message, 'chore(release):')"
```

This prevents the version-bump commit from triggering another workflow run. As a belt-and-suspenders, bot commits also include `[skip release]` in the message body.

**Concurrency guard:**

```yaml
concurrency:
  group: release
  cancel-in-progress: false
```

Queues concurrent runs instead of canceling, ensuring sequential releases if two PRs merge quickly.

### Override Mechanisms

- **Skip release:** Include `[skip release]` in any commit message → workflow exits without releasing
- **Force major bump:** Use `feat!:` prefix or `BREAKING CHANGE:` footer → major version bump
- **Manual trigger:** `workflow_dispatch` with optional inputs:
  ```yaml
  workflow_dispatch:
    inputs:
      bump_override:
        description: "Force bump type (major/minor/patch), or leave empty for auto-detect"
        required: false
      dry_run:
        description: "Preview what would happen without releasing"
        type: boolean
        default: false
  ```
- **No releasable commits:** If no `feat:` or `fix:` commits since last tag → exit without releasing

### Conventional Commit Parsing

A bash function `_parse_conventional_commits` in `lib/release.sh`:

1. Get commits between last tag and HEAD: `git log $LAST_TAG..HEAD --oneline`
2. Scan each commit for prefixes:
   - `feat!:` or body contains `BREAKING CHANGE:` → **major**
   - `feat:` → **minor**
   - `fix:` → **patch**
   - `docs:`, `chore:`, `refactor:`, `test:`, `ci:` → no bump (but included in release notes)
3. Determine highest bump level: major > minor > patch > none
4. If `[skip release]` found in any commit message → return `none`
5. Output: `BUMP_TYPE` (major/minor/patch/none) + categorized commit messages

**First release handling:** When no previous tag exists, use `git rev-list --max-parents=0 HEAD` to get the initial commit and scan from there. Alternatively, as a prerequisite, create a `v0.1.0` tag manually on the current main before enabling the workflow (documented in setup instructions).

### Semver Arithmetic

Pure bash version bumping:

```bash
IFS='.' read -r major minor patch <<< "$current_version"
case "$bump_type" in
  major) new_version="$((major + 1)).0.0" ;;
  minor) new_version="${major}.$((minor + 1)).0" ;;
  patch) new_version="${major}.${minor}.$((patch + 1))" ;;
esac
```

### Version Bump Script

**File:** `scripts/bump-version.sh`

A standalone bash script callable by both the GitHub Actions workflow and locally via `devflow version-bump`:

```bash
# Usage: scripts/bump-version.sh <new_version> [project_dir]
```

Updates all version-bearing files using `sed`:

| File | Pattern | Replacement |
|------|---------|-------------|
| `Makefile` | `VERSION := X.Y.Z` | `VERSION := <new>` |
| `lib/utils.sh` | `DEVFLOW_VERSION="X.Y.Z"` | `DEVFLOW_VERSION="<new>"` |
| `devflow-plugin/.claude-plugin/plugin.json` | `"version": "X.Y.Z"` | `"version": "<new>"` |
| `devflow-plugin/.claude-plugin/marketplace.json` | `"version": "X.Y.Z"` | `"version": "<new>"` |
| `devflow-plugin/commands/*.md` | `[devflow vX.Y.Z]` | `[devflow v<new>]` |

This list mirrors the watchdog's `sensitive-files.conf` mechanical version entries. The script is the write-side counterpart to `check_version_consistency` in `lib/watch.sh` (read-side).

### GitHub Actions Workflow

**File:** `.github/workflows/release.yml`

**Single-push architecture:** All commits (version bump + formula update) are done locally in the workflow, then pushed once. This avoids the inconsistency window of multiple pushes.

**Steps:**

```
 1. Checkout code (full history: fetch-depth: 0)
 2. Get latest tag: git describe --tags --abbrev=0 2>/dev/null || use initial commit
 3. Parse conventional commits since last tag
    └─ If bump_type == "none" → exit 0 (no release)
    └─ If workflow_dispatch with bump_override → use override
 4. Compute new version via semver arithmetic
 5. Run scripts/bump-version.sh <new_version>
 6. Run make check-version to validate consistency
 7. Create tarball from working tree: make release
 8. Compute SHA256: sha256sum dist/devflow-<version>.tar.gz
 9. Update Formula/devflow.rb with new release asset URL and SHA
10. Single commit: "chore(release): v<new_version> [skip release]"
11. Create git tag: v<new_version>
12. Push commit + tag to main (single push)
13. Create GitHub Release via gh:
    - Tag: v<new_version>
    - Title: "devflow v<new_version>"
    - Body: auto-generated release notes
    - Assets: dist/devflow-<version>.tar.gz, install.sh
```

**SHA256 portability:** Uses `sha256sum` (available on Ubuntu GHA runners) with fallback:
```bash
_sha256() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$1" | cut -d' ' -f1; }
```

**Tarball structure:** The `make release` tarball contains a `devflow/` root directory. The Formula's `install` block must account for this (`cd "devflow"` after extraction). This is documented in the Formula itself.

### Release Notes Template

Auto-generated from categorized commits:

```markdown
## What's New

### Features
- <feat commit messages>

### Fixes
- <fix commit messages>

### Other Changes
- <refactor/docs/chore/test commits>

---

## Install / Update

**Quick install:**
curl -fsSL https://raw.githubusercontent.com/AndreJorgeLopes/devflow/main/install.sh | bash

**Homebrew:**
brew upgrade devflow

**From source:**
git pull && make install

**Then run:** devflow init
```

### Homebrew Formula Update

The formula lives at `Formula/devflow.rb` in the same repo. Updated as part of the single release commit (step 9):

1. Compute SHA256 of tarball
2. Update `Formula/devflow.rb`:
   - `url` → `https://github.com/AndreJorgeLopes/devflow/releases/download/v<version>/devflow-<version>.tar.gz`
   - `sha256` → computed hash
3. Included in the same `chore(release):` commit — no separate push

### Local CLI Integration

**`devflow version-bump <version>`** — wraps `scripts/bump-version.sh`:

- Added as a dispatch case in `bin/devflow`
- Runs `check_version_consistency` after bump to validate
- Useful for manual overrides or pre-merge preparation

**`devflow release`** — local release preview:

- Shows what the next version would be based on conventional commits since last tag
- Shows draft release notes (categorized commit list)
- Validates all version files are consistent
- Does NOT create the release (that's CI's job)

## New Files

| File | Purpose |
|------|---------|
| `.github/workflows/release.yml` | GitHub Actions release workflow |
| `scripts/bump-version.sh` | Standalone version bump script (used by CI and locally) |
| `lib/release.sh` | CLI functions: `devflow_version_bump`, `devflow_release_preview`, `_parse_conventional_commits` |

## Modified Files

| File | Change |
|------|--------|
| `bin/devflow` | Add `source lib/release.sh`, `version-bump` and `release` dispatch cases, help text |
| `CLAUDE.md` | Document release process and conventional commit requirements |
| `Makefile` | Update `.PHONY` with `version-bump` |

## Testing

| Test | Description |
|------|-------------|
| `bump_version_updates_all_files` | `scripts/bump-version.sh` updates all version locations correctly |
| `bump_version_idempotent` | Running bump twice with same version produces no diff |
| `parse_conventional_commits_minor` | `feat:` commits produce minor bump |
| `parse_conventional_commits_major` | `feat!:` or `BREAKING CHANGE:` produces major bump |
| `parse_conventional_commits_skip` | `[skip release]` produces no bump |
| `parse_conventional_commits_no_releasable` | Only `chore:` commits produce no bump |
| `parse_conventional_commits_first_release` | No previous tag → scans from initial commit |
| `semver_arithmetic` | Bumping 0.1.0 minor → 0.2.0, patch → 0.1.1, major → 1.0.0 |
| `formula_update_replaces_url_and_sha` | Formula/devflow.rb gets correct URL and SHA after update |

## Failure Recovery

| Failure Point | State | Recovery |
|---------------|-------|----------|
| Before push (steps 1-11) | No changes on remote | Safe — re-run workflow |
| Push succeeds, `gh release create` fails (step 13) | Tag exists, no release | `gh release create v<version> --tag v<version>` manually, or delete tag and re-push |
| Tarball upload fails | Release exists without assets | `gh release upload v<version> dist/devflow-<version>.tar.gz install.sh` |
| Formula was not updated (pre-single-commit era) | Version files updated, Formula stale | Run `make check-formula` to detect, manually update and push |

Since all changes are in a single commit + single push, partial failure is limited to the GitHub Release creation step (which can be retried).

## Design Decisions

1. **Custom workflow over release-please** — release-please adds external dependency and is opinionated about file structure. Custom bash aligns with devflow's zero-deps philosophy.
2. **Conventional commits** — standard, well-understood, already adopted in the project.
3. **Same-repo Homebrew formula** — avoids a separate tap repo. Acceptable for single-formula projects.
4. **Standalone bump script** — `scripts/bump-version.sh` works in both CI and local contexts.
5. **Commit-message overrides** — `[skip release]` and `BREAKING CHANGE:` follow conventional commits conventions.
6. **Single-push architecture** — all changes (version bump + formula update) in one commit, pushed once. Eliminates race conditions and inconsistency windows.
7. **Separate `lib/release.sh`** — release functions live in their own file following devflow's one-lib-per-subcommand convention, not in `lib/watch.sh` (which is the watchdog).
8. **Re-trigger prevention via commit message filter** — `if: "!startsWith(github.event.head_commit.message, 'chore(release):')"` prevents the workflow's own commits from triggering another run. `[skip release]` in bot commit bodies provides a second layer.

## Alternatives Considered

### release-please (rejected)
Battle-tested but adds external dependency. Opinionated about version file locations — devflow has 5+ non-standard locations. The intermediate "Release PR" adds friction.

### Tag-triggered release (rejected)
Requires manual tagging. Doesn't satisfy "automatic on merge to main" requirement.

### GoReleaser (rejected)
Designed for compiled Go binaries. Irrelevant for a bash CLI.

### git-cliff for changelog (deferred)
Could generate CHANGELOG.md from conventional commits. Not in v1 scope. Can be added later.

### Dual-push (version commit + formula commit separately) (rejected)
Creates a race condition window where main has updated versions but stale Formula. Single-push eliminates this.

## Future Extensions

- **CHANGELOG.md generation** using git-cliff or custom bash
- **Separate Homebrew tap** if project outgrows single-repo formula
- **Release candidate (RC) tags** for pre-release testing
- **`devflow release` showing draft release notes** for preview before pushing
