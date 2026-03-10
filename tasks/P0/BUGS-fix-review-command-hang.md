---
id: BUGS-fix-review-command-hang
title: "Fix devflow review command hanging on Claude Code invocation"
priority: P0
category: bugs
status: open
depends_on: []
estimated_effort: S
files_to_touch:
  - bin/devflow
---

## Problem

`devflow review` hangs indefinitely at:

```
── Running self-review ──
[devflow] Invoking Claude Code for review...
```

## Root Cause

`devflow_review()` (bin/devflow:110-113) invokes `claude --print` without
`--permission-mode plan`, so Claude Code may block waiting for interactive
permission prompts that never get answered (stdin is the piped diff, not a TTY).

Compare with the working `_run_review_claude()` in `lib/check.sh:94-99` which
correctly passes `--permission-mode plan --allowedTools "Read,Glob,Grep"`.

## Fix

Align `devflow_review` with the pattern in `_run_review_claude`:

1. Add `--permission-mode plan` to prevent interactive permission prompts
2. Add `--allowedTools "Read,Glob,Grep"` to restrict tool access
3. Consider adding a `--system-prompt` with the CLAUDE.md content instead of
   relying on claude auto-detecting it (more explicit and reliable)
4. Remove `2>/dev/null` or redirect to a log file so errors aren't silently swallowed

## Verification

- Run `devflow review` on a branch with uncommitted changes
- Confirm it completes without hanging and outputs review results
