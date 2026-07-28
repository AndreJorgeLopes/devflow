#!/usr/bin/env bash
# devflow/lib/hooks/branch-guard.sh
# Claude Code PreToolUse(Bash) hook — thin wrapper around branch-guard.py.
#
# Blocks a git checkout/switch that would move a repo's PRIMARY clone onto a
# non-base feature branch (worktree-flow repos only). See branch-guard.py.
#
# Fail-open: if python3 is unavailable we must NOT block the agent's command.
# The JSON payload on stdin passes straight through to python (we don't read it
# here), so `exec` hands it off intact.
command -v python3 >/dev/null 2>&1 || exit 0
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/branch-guard.py"
