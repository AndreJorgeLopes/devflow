---
id: BUGS-fix-help-escape-chars
title: "Fix Help CLI Escape Character Display"
priority: P0
category: bugs
status: open
depends_on: []
estimated_effort: S
files_to_touch:
  - bin/devflow
  - lib/utils.sh
---

# Fix Help CLI Escape Character Display

## Context

Devflow is a CLI tool (`bin/devflow`) that sources shared utilities from `lib/utils.sh`. The utils file defines color variables using ANSI escape sequences:

```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'
# ... etc
```

The `usage()` function in `bin/devflow` (line 31-74) uses these variables inside a `cat <<EOF` heredoc to render colorized help output:

```bash
usage() {
  cat <<EOF
${BOLD}devflow${RESET} v${DEVFLOW_VERSION} — AI dev environment orchestrator
...
  ${CYAN}init${RESET} [project-dir]          Initialize a project with all 6 layers
...
EOF
}
```

## Problem Statement

When running `devflow help`, ANSI escape codes appear as literal text (e.g., `\033[0;36m`) instead of being rendered as colors. This happens because:

1. The color variables in `lib/utils.sh` are defined as `CYAN='\033[0;36m'` — using **single quotes**, which means bash stores the literal string `\033[0;36m` rather than the actual escape byte.
2. The `cat <<EOF` heredoc **does** expand variables (so `${CYAN}` is replaced), but it replaces them with the literal `\033[0;36m` string because that's what the variable contains.
3. `cat` outputs exactly what it receives — it does not interpret escape sequences.

The logging functions (`log`, `info`, `warn`, etc.) work correctly because they use `printf`, which **does** interpret `\033` escape sequences. But `cat <<EOF` does not.

## Desired Outcome

Running `devflow help` should display properly colorized output in any terminal that supports ANSI colors. No raw escape codes should be visible. The fix should also work when piped (graceful degradation — escape codes present but not harmful).

## Implementation Guide

There are two valid approaches. **Approach A is recommended** because it's minimal and keeps the heredoc readable.

### Approach A: Use `$'...'` syntax for color variable definitions (Recommended)

In `lib/utils.sh`, change all color variable definitions from single-quoted `'\033[...'` to ANSI-C quoting `$'\033[...'`. This makes bash interpret the escape sequences at assignment time, so the variables contain actual escape bytes.

**File:** `lib/utils.sh`, lines 8-15

Change:

```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
```

To:

```bash
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'
```

That's it. No other changes needed. The `printf`-based logging functions will continue to work (printf handles both raw bytes and `\033` literals). The `cat <<EOF` heredoc in `usage()` will now receive actual escape bytes and display colors correctly.

### Approach B (Alternative): Replace `cat <<EOF` with `printf`

If Approach A is rejected for any reason, change the `usage()` function in `bin/devflow` to use `printf '%b'` instead of `cat <<EOF`. The `%b` format specifier interprets backslash escape sequences:

```bash
usage() {
  printf '%b\n' "
${BOLD}devflow${RESET} v${DEVFLOW_VERSION} — AI dev environment orchestrator
...
"
}
```

This is more invasive and harder to read. Prefer Approach A.

### Verification that nothing else breaks

After making the change in Approach A, verify that:

- All `printf`-based logging functions still produce colored output (they will — printf handles raw escape bytes fine)
- The `section()`, `detail()`, `ok()`, `fail()`, `skip()` functions still work
- The `devflow status` command still shows colored layer headers (it uses `printf` with `${BOLD}` etc.)

## Acceptance Criteria

- [ ] `devflow help` displays colored output (cyan commands, bold headers) in a standard terminal
- [ ] `devflow help 2>&1 | cat -v` shows `^[[0;36m` (interpreted escape) not literal `\033[0;36m`
- [ ] `devflow status` still displays colored output correctly
- [ ] All logging functions (`log`, `info`, `warn`, `err`, `section`, `ok`, `fail`) still produce colored output
- [ ] No raw `\033` strings visible anywhere in CLI output

## Technical Notes

- **Single quotes vs `$'...'`:** In bash, `'\033'` is the literal 4-character string `\033`. The `$'\033'` syntax (ANSI-C quoting) interprets it as the actual ESC byte (0x1B). This is a common bash gotcha.
- **printf compatibility:** `printf` interprets `\033` in format strings regardless of whether the variable contains the literal or the byte. So the existing logging functions work either way. This change is safe.
- **Heredoc behavior:** `cat <<EOF` expands variables but does NOT interpret escape sequences in their values. Only `cat <<$'EOF'` or printf-based approaches handle that.
- **Terminal detection:** This fix does not add tty detection (disabling colors when piped). That would be a separate enhancement. Currently the escape bytes will be present in piped output, which is standard behavior for most CLI tools.

## Verification

```bash
# 1. Check that help shows colors (visual inspection)
devflow help

# 2. Check that escape codes are interpreted (not literal)
devflow help 2>&1 | cat -v | grep -c '\\033'
# Expected: 0 (no literal \033 sequences)

# 3. Check that escape bytes ARE present (colors work)
devflow help 2>&1 | cat -v | grep -c '\^'
# Expected: >0 (interpreted escape sequences show as ^[[ in cat -v)

# 4. Verify other commands still have colored output
devflow version
devflow status 2>&1 | head -5
```
