#!/usr/bin/env bash
# devflow/lib/hooks/stop-finish-prompt.sh
# Claude Code Stop hook — prompts user to run finish-feature flow
# Protocol: exit 2 = block stop and re-activate agent, stderr = message to agent

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

# Check if a PR/MR already exists for this branch — if so, allow stop
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../utils.sh"

provider="$(detect_vcs_provider 2>/dev/null)" || provider="unknown"
pr_exists=false

case "$provider" in
  github)
    count="$(gh pr list --head "$current_branch" --json number --jq 'length' 2>/dev/null || echo "0")"
    [[ "$count" -gt 0 ]] && pr_exists=true
    ;;
  gitlab)
    count="$(glab mr list --source-branch "$current_branch" --mine 2>/dev/null | grep -c "^!" || echo "0")"
    [[ "$count" -gt 0 ]] && pr_exists=true
    ;;
esac

if [[ "$pr_exists" == "true" ]]; then
  exit 0
fi

# No PR/MR found — block stop and prompt for finish-feature
echo '[INTENTIONAL "ERROR"] Unmerged work detected — prompting for finish-feature flow.' >&2

exit 2
