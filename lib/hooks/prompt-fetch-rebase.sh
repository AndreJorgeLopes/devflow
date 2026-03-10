#!/usr/bin/env bash
# devflow/lib/hooks/prompt-fetch-rebase.sh
# Claude Code UserPromptSubmit hook — fetches origin, auto-rebases when safe,
# injects context for the AI when conflicts are detected.
#
# Protocol (UserPromptSubmit):
#   exit 0 + stdout  → allow prompt, inject stdout as AI-visible context
#   exit 2 + stderr  → BLOCK prompt entirely (user's message never reaches AI)
#
# This hook NEVER uses exit 2 — blocking creates infinite loops because
# the AI can't act on the message or process user responses.

set -euo pipefail

# Read the hook payload from stdin
payload="$(cat)"

# Extract session ID for the opt-out and notified flag files
session_id="$(echo "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id', 'unknown'))" 2>/dev/null || echo "unknown")"
optout_file="/tmp/devflow-no-rebase-${session_id}"
notified_file="/tmp/devflow-rebase-notified-${session_id}"

# If user opted out of rebase for this session, skip entirely
if [[ -f "$optout_file" ]]; then
  exit 0
fi

# Only act on feature branches
current_branch="$(git branch --show-current 2>/dev/null || echo "")"
if [[ -z "$current_branch" ]] || [[ "$current_branch" == "main" ]] || [[ "$current_branch" == "master" ]]; then
  exit 0
fi

# Detect main branch name
main_branch="main"
if ! git rev-parse --verify "$main_branch" >/dev/null 2>&1; then
  main_branch="master"
  if ! git rev-parse --verify "$main_branch" >/dev/null 2>&1; then
    exit 0
  fi
fi

# Fetch origin (suppress output — this is background housekeeping)
if ! git fetch origin >/dev/null 2>&1; then
  # Network failure — skip silently, don't block the user
  exit 0
fi

# Update local main ref to match origin (without checkout)
git update-ref "refs/heads/${main_branch}" "origin/${main_branch}" 2>/dev/null || true

# Check if main has new commits since our branch point
merge_base="$(git merge-base HEAD "${main_branch}" 2>/dev/null || echo "")"
if [[ -z "$merge_base" ]]; then
  exit 0
fi

main_ahead="$(git rev-list --count "${merge_base}..${main_branch}" 2>/dev/null || echo "0")"
if [[ "$main_ahead" -eq 0 ]]; then
  exit 0
fi

# Main has new commits — check if they overlap with our changes
our_files="$(git diff --name-only "${main_branch}...HEAD" 2>/dev/null || echo "")"
main_new_files="$(git diff --name-only "${merge_base}..${main_branch}" 2>/dev/null || echo "")"

# Find overlapping files
overlap=""
if [[ -n "$our_files" ]] && [[ -n "$main_new_files" ]]; then
  overlap="$(comm -12 <(echo "$our_files" | sort) <(echo "$main_new_files" | sort) || echo "")"
fi

if [[ -z "$overlap" ]]; then
  # No overlapping files — safe to auto-rebase
  if git rebase "${main_branch}" >/dev/null 2>&1; then
    rm -f "$notified_file"
    echo "[devflow] Auto-rebased on ${main_branch} (${main_ahead} new commits, no conflicts with your changes)."
  else
    git rebase --abort >/dev/null 2>&1 || true
    echo "[devflow] ${main_ahead} new commits on ${main_branch}. Auto-rebase failed — you may want to rebase manually."
  fi
  exit 0
fi

# Overlapping files detected — only notify once per session to avoid spamming.
# The AI handles the interaction and creates the opt-out file if needed.
if [[ -f "$notified_file" ]]; then
  exit 0
fi
touch "$notified_file"

# Inject context for the AI via stdout (exit 0 = allow prompt through)
file_count="$(echo "$overlap" | wc -l | tr -d ' ')"
file_list="$(echo "$overlap" | head -10)"
more_note=""
if [[ "$file_count" -gt 10 ]]; then
  more_note="... and $((file_count - 10)) more files
"
fi

cat <<CONTEXT
[devflow] Upstream conflict warning: \`${main_branch}\` has ${main_ahead} new commit(s) that touch ${file_count} file(s) you've also changed:

${file_list}
${more_note}
Ask the user how they'd like to handle this before continuing with their request:
1. Let me handle it — rebase and resolve merge conflicts
2. I'll fix it myself — stop and let the user resolve manually
3. Ignore for this session — stop checking until next session

If the user picks option 3, run: touch ${optout_file}
CONTEXT

exit 0
