# Auto-Reinstall

**Date:** 2026-03-18
**Status:** Draft
**Scope:** Automatically update local devflow installation when main gets new commits
**Depends on:** Sensitive File Watchdog (`lib/watch.sh`) for merge detection, Release Pipeline for versioned releases

## Problem

When developing devflow, the installed binary (`~/.local/bin/devflow`) and its libs (`~/.local/share/devflow/`) are copies from `make install`. After merging a feature to main, the installed version goes stale until the developer remembers to re-run `make install`. This means other projects on the same machine that use devflow get an outdated version of commands, hooks, and lib functions.

## Solution

Extend the Sensitive File Watchdog's background watcher (`_watch_run` in `lib/watch.sh`) with an additional step: after detecting new commits on main, check if the local devflow install is stale and auto-update. Uses SHA-based staleness detection (not version strings) to catch all changes, not just version bumps.

## Architecture

### Staleness Detection

Instead of comparing version strings (which only change on releases), compare the `origin/main` SHA against a stored "last-installed SHA". This catches ALL changes to main — code fixes, new commands, hook updates — not just version bumps.

**State file:** `~/.devflow/.last-installed-sha` (global, not per-project)

### Detection Logic

Added as a new step in `_watch_run`, after the sensitive file checks (step 9) and before the SHA tracking update (step 11):

```
10. Auto-reinstall check (only if opted in):
    a. Guard: skip if .devflow/.dev-setup does not contain "auto_reinstall=true"
    b. Get last-installed SHA:
       - cat ~/.devflow/.last-installed-sha 2>/dev/null || echo ""
    c. Compare against origin/main SHA (already computed in step 2):
       - If equal → skip silently
       - If different → detect install mode and update
    d. Detect install mode:
       - installed_path="$(command -v devflow)"
       - If symlink → "link" (make link)
       - If path contains /opt/homebrew/ or /usr/local/Cellar/ → "brew"
       - If regular file → "install" (make install)
       - If not found → "none" (skip)
    e. Update (with error handling):
       - Dev/link mode: cd "$project_dir" && make link
       - Copy/install mode: cd "$project_dir" && make install
       - Brew mode: skip with warning "devflow is managed by Homebrew, run: brew upgrade devflow"
       - None: skip silently
    f. On success:
       - Write origin/main SHA to ~/.devflow/.last-installed-sha
       - Notify: "devflow auto-updated to <SHA_SHORT> (via make <target>)"
    g. On failure:
       - Do NOT update .last-installed-sha (next cron run retries)
       - Notify: "devflow auto-update failed: make <target> exited with code N"
       - Log full error to ~/.devflow/watch.log
```

### Guard: Opt-in via `devflow watch setup`

The auto-reinstall is **opt-in**, not heuristic-based. During `devflow watch setup`, the setup wizard asks:

```
This appears to be the devflow source repo.
Enable auto-reinstall? (Updates your local devflow binary when main gets new commits)
[y/N]
```

If yes, writes `auto_reinstall=true` to `.devflow/.dev-setup`. The `_auto_reinstall_check` function reads this flag before doing anything. This avoids the fragile repo-name check and makes the feature explicitly controllable.

### Install Mode Detection

```bash
_detect_install_mode() {
  local devflow_path
  devflow_path="$(command -v devflow 2>/dev/null || echo "")"
  [[ -z "$devflow_path" ]] && echo "none" && return

  # Resolve symlinks for Homebrew detection
  local resolved_path
  resolved_path="$(readlink -f "$devflow_path" 2>/dev/null || echo "$devflow_path")"

  if [[ -L "$devflow_path" ]] && [[ "$resolved_path" != */Cellar/* ]] && [[ "$resolved_path" != */homebrew/* ]]; then
    echo "link"  # direct symlink to repo → make link
  elif [[ "$resolved_path" == */opt/homebrew/* ]] || [[ "$resolved_path" == */usr/local/Cellar/* ]] || [[ "$resolved_path" == */home/linuxbrew/* ]]; then
    echo "brew"  # Homebrew-managed
  else
    echo "install"  # copy → make install
  fi
}
```

This function lives in `lib/watch.sh` alongside the other watchdog helpers (not in `lib/utils.sh`) because it is specific to the auto-reinstall feature and not a general utility.

### Error Handling

The `make` invocation is wrapped with exit code capture:

```bash
local make_target
case "$install_mode" in
  link)    make_target="link" ;;
  install) make_target="install" ;;
  brew)
    _watch_notify "devflow is managed by Homebrew. Run: brew upgrade devflow" "$headless"
    return 0
    ;;
  none) return 0 ;;
esac

if (cd "$project_dir" && make "$make_target" 2>&1); then
  echo "$origin_sha" > "${HOME}/.devflow/.last-installed-sha"
  _watch_notify "devflow auto-updated to $(echo "$origin_sha" | head -c 7) (via make $make_target)" "$headless"
else
  _watch_notify "devflow auto-update FAILED: make $make_target exited with code $?" "$headless"
  # Do NOT update .last-installed-sha — next cron run will retry
fi
```

### Dry-Run Support

When `_watch_run` is called with `--dry-run`, the auto-reinstall check reports what it WOULD do:

```
DRY RUN — Would run make install (installed SHA: abc1234, origin/main SHA: def5678)
```

### Trigger Points

1. **Background cron** (`--headless`): After sensitive file checks, runs the reinstall check silently.
2. **Post-merge hook** (`--immediate`): Immediate reinstall when you pull main.

### Notification

Uses the existing `_watch_notify` function:
- Cron: macOS `osascript` / Linux `notify-send` + log
- Post-merge: terminal bell + stderr message
- Always: logged to `~/.devflow/watch.log`

## New Files

None — this is a pure extension to `lib/watch.sh`.

## Modified Files

| File | Change |
|------|--------|
| `lib/watch.sh` | Add `_detect_install_mode`, `_auto_reinstall_check` functions; call from `_watch_run` after step 9; add `auto_reinstall` opt-in to `_watch_setup` |
| `CLAUDE.md` | Document auto-reinstall behavior in the Sensitive File Watchdog section |

## State Files

| File | Purpose |
|------|---------|
| `~/.devflow/.last-installed-sha` | SHA of origin/main at last successful install (global, not per-project) |

## Testing

| Test | Description |
|------|-------------|
| `detect_install_mode_symlink` | Returns "link" when devflow binary is a symlink (not Homebrew) |
| `detect_install_mode_copy` | Returns "install" when devflow binary is a regular file |
| `detect_install_mode_brew` | Returns "brew" when devflow path contains Homebrew prefix |
| `detect_install_mode_missing` | Returns "none" when devflow is not in PATH |
| `auto_reinstall_skips_when_not_opted_in` | Does not run when `auto_reinstall=true` is absent from `.dev-setup` |
| `auto_reinstall_skips_matching_sha` | No action when installed SHA matches origin/main |
| `auto_reinstall_runs_make_on_stale_sha` | Calls `make install` (or `make link`) when SHAs differ |
| `auto_reinstall_does_not_update_sha_on_failure` | `.last-installed-sha` unchanged when `make install` fails |
| `auto_reinstall_brew_warns_only` | Sends notification but does not run `make` for Homebrew installs |
| `auto_reinstall_respects_dry_run` | Prints what would happen without executing |

## Design Decisions

1. **SHA-based staleness, not version-based** — version strings only change on releases. SHA comparison catches every commit to main: bug fixes, new commands, hook changes. Uses the same SHA tracking pattern as the watchdog's `.last-checked-sha`.
2. **Opt-in via `.dev-setup` flag** — avoids fragile heuristics like repo-name checking. The `devflow watch setup` wizard explicitly asks whether to enable auto-reinstall. Only fires when the developer has intentionally opted in.
3. **Homebrew detection as third mode** — prevents `make install` from creating a competing install alongside a Homebrew-managed one. Warns the user to use `brew upgrade` instead.
4. **Error handling with retry** — on failure, the SHA tracking file is NOT updated, so the next cron cycle retries. Notification alerts the developer to investigate.
5. **Watchdog extension, not separate mechanism** — the watcher already polls origin/main and detects new commits. Adding a reinstall check is ~30 lines of bash.
6. **Dev mode only** — only handles `make install` / `make link` / Homebrew warning. Plugin cache updates (`make plugin-install`) are a separate concern.

## Alternatives Considered

### Version-string comparison (rejected)
Only detects changes when VERSION is bumped. Misses code changes between releases — the most common scenario during active development.

### Repo-name heuristic guard (rejected)
Checking `basename $(git rev-parse --show-toplevel) == "devflow"` breaks when the repo is cloned into a differently-named directory or accessed via a worktree. Opt-in flag is more robust.

### Separate post-merge hook (rejected)
Would duplicate merge-detection logic already in the watcher.

### Finish-feature step only (rejected)
Only works when you personally finish a feature. Doesn't catch collaborator merges.

## Future Extensions

- **Plugin cache reinstall** — add `make plugin-install` for end-user installs
- **Homebrew auto-upgrade** — run `brew upgrade devflow` automatically (requires careful testing)
- **Lockfile for concurrent safety** — `flock`-based lock around `make install` to prevent overlapping cron jobs
- **Rollback** — if `make install` fails, revert to previous version from a backup
