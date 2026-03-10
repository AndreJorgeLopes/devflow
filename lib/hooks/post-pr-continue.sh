#!/usr/bin/env bash
# devflow/lib/hooks/post-pr-continue.sh
# Claude Code PostToolUse hook — nudges agent to continue finish-feature after PR/MR creation
# Protocol: exit 0 = silent, exit 2 = show stderr to agent (non-blocking feedback)

set -euo pipefail

# Read the PostToolUse payload from stdin
payload="$(cat)"

# Only act on Bash tool calls
tool_name="$(echo "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name', ''))" 2>/dev/null || echo "")"
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

# Extract the command that was executed
command="$(echo "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))" 2>/dev/null || echo "")"

# Only act if the command created a PR or MR
if [[ "$command" != *"gh pr create"* ]] && [[ "$command" != *"glab mr create"* ]]; then
  exit 0
fi

# Inject continuation context — stderr is shown to the agent as non-blocking feedback
cat >&2 <<'MSG'
[devflow] PR/MR created successfully. The finish-feature flow is not complete yet.
Continue with the remaining steps:
- Retain session learnings via Hindsight (architecture decisions, gotchas, bug fixes)
- Present the feature completion summary to the user
- Offer worktree cleanup options
Do NOT stop until all remaining finish-feature steps are complete.
MSG

exit 2
