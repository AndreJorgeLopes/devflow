#!/usr/bin/env bash
# devflow/lib/hooks/stop-finish-prompt.sh
# Claude Code Stop hook — prompts user to run finish-feature flow
# Protocol: reads JSON from stdin, exit 0 = allow stop, exit 2 = block (re-activate)

set -euo pipefail

# Read the Stop hook payload from stdin
payload="$(cat)"

# Prevent infinite loops: if this Stop was triggered by a previous hook, allow it
stop_hook_active="$(echo "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null || echo "False")"
if [[ "$stop_hook_active" == "True" ]] || [[ "$stop_hook_active" == "true" ]]; then
  exit 0
fi

# Only act on feature branches — not main/master
current_branch="$(git branch --show-current 2>/dev/null || echo "")"
if [[ -z "$current_branch" ]] || [[ "$current_branch" == "main" ]] || [[ "$current_branch" == "master" ]]; then
  exit 0
fi

# Only act if there are commits ahead of main
main_branch="main"
if ! git rev-parse --verify "$main_branch" >/dev/null 2>&1; then
  main_branch="master"
  if ! git rev-parse --verify "$main_branch" >/dev/null 2>&1; then
    exit 0
  fi
fi

commits_ahead="$(git rev-list --count "${main_branch}..HEAD" 2>/dev/null || echo "0")"
if [[ "$commits_ahead" -eq 0 ]]; then
  exit 0
fi

# We're on a feature branch with commits — prompt the user
cat >&2 <<'PROMPT'
You just finished your response on a feature branch with commits ahead of main.

Before ending the session, ask the user:

> **Ready to wrap up?** You have work on this branch that hasn't been merged yet. Would you like to:
>
> 1. **Run the finish-feature flow** — verification, PR creation, session summary, and visualizations (`/devflow:finish-feature`)
> 2. **Continue working** — ask a follow-up question or keep iterating

Wait for the user to choose before proceeding. Do NOT run finish-feature automatically.
PROMPT

exit 2
