# Skills Absolute Path Resolution

**Date:** 2026-03-18
**Status:** Draft
**Problem:** Devflow commands reference `skills/` files via relative paths that break outside the devflow repo.

## Problem

Devflow commands are symlinked globally (`~/.claude/commands/devflow/` -> `<DEVFLOW_ROOT>/devflow-plugin/commands/`). Two commands instruct the AI to `Read skills/...` using relative paths:

1. `writing-plans.md` -> `skills/superpowers-wrappers/writing-plans.md`
2. `finish-feature.md` -> `skills/visualizations/update-visualizations.md`

These paths resolve relative to CWD. Inside the devflow repo they work; in any other project they fail with: "The devflow extension file skills/superpowers-wrappers/writing-plans.md doesn't exist in this repo."

## Solution

Two-layer path resolution: a `devflow root` CLI subcommand as the primary API, with symlink-based fallback.

### 1. `devflow root` subcommand

Add `root) devflow_root ;;` to the dispatcher case statement in `bin/devflow`. The `devflow_root()` function already exists (line 30) and prints `$DEVFLOW_ROOT`. No new function needed.

Add `root` to the `usage()` function as a plumbing command.

```bash
devflow root  # prints: /Users/someone/dev/devflow
```

### 2. Symlink-based fallback

When `devflow` isn't in PATH, resolve from the commands symlink. Use `readlink -f` to handle any relative symlinks (though `devflow init` always creates absolute symlinks):

```bash
readlink -f ~/.claude/commands/devflow | sed 's|/devflow-plugin/commands$||'
```

Note: `readlink -f` is available on macOS 12.3+ and all Linux.

### 3. Standard resolver preamble

Commands that need skill files include this block before any `Read skills/...` instruction:

```markdown
**Step 0: Resolve devflow root.** Run this command and capture its output:
\`\`\`bash
devflow root 2>/dev/null || readlink -f ~/.claude/commands/devflow | sed 's|/devflow-plugin/commands$||'
\`\`\`
Store the result as DEVFLOW_ROOT. All `Read` instructions below that reference `skills/` use this path as the prefix.
```

### 4. Updated commands

**`writing-plans.md`:** Replace the relative path instruction with the resolver preamble, then `Read <DEVFLOW_ROOT>/skills/superpowers-wrappers/writing-plans.md`.

**`finish-feature.md`:** Replace the relative path at line 62 with the resolver preamble, then `Read <DEVFLOW_ROOT>/skills/visualizations/update-visualizations.md`.

## Files Changed

| File | Change |
|------|--------|
| `bin/devflow` | Add `root` subcommand case |
| `devflow-plugin/commands/writing-plans.md` | Add resolver preamble, use absolute path |
| `devflow-plugin/commands/finish-feature.md` | Add resolver preamble, use absolute path |

## Testing

- `devflow root` prints the correct absolute path when run directly
- `devflow root` resolves correctly when `bin/devflow` is itself a symlink (e.g., `~/.local/bin/devflow` -> `<DEVFLOW_ROOT>/bin/devflow`) — the `_resolve_source()` function already handles this
- Symlink fallback works: `readlink -f ~/.claude/commands/devflow | sed 's|/devflow-plugin/commands$||'`
- Fallback when `devflow` is NOT in PATH produces a valid absolute path
- Add a bats unit test for the `root` subcommand
- Existing tests pass: `make test`, `make test-unit`

## Non-goals

- Symlinking the entire `skills/` directory globally
- Changing how `devflow init` sets up symlinks
- Modifying any skill wrapper file content (only the command files that reference them change)
