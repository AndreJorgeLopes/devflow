#!/usr/bin/env bash
# devflow/lib/hooks/pending-reviews-notify.sh
# Claude Code UserPromptSubmit hook — notifies when sensitive file reviews are pending.
#
# Protocol (UserPromptSubmit):
#   exit 0 + stdout → allow prompt, inject stdout as AI-visible context
#   This hook NEVER uses exit 2.

set -euo pipefail

# Read the hook payload from stdin (required by protocol)
payload="$(cat)"

# Extract session ID for the notification-spam guard
session_id="$(echo "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id', 'unknown'))" 2>/dev/null || echo "unknown")"
notified_file="/tmp/devflow-pending-notified-${session_id}"

# If already notified this session, skip
if [[ -f "$notified_file" ]]; then
  exit 0
fi

# Find project root
project_dir="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -z "$project_dir" ]]; then
  exit 0
fi

# Check for pending files
pending_fixes="${project_dir}/.devflow/pending-fixes.json"
pending_reviews="${project_dir}/.devflow/pending-reviews.json"

has_pending=0
if [[ -f "$pending_fixes" ]] && [[ -s "$pending_fixes" ]]; then
  has_pending=1
fi
if [[ -f "$pending_reviews" ]] && [[ -s "$pending_reviews" ]]; then
  has_pending=1
fi

if [[ "$has_pending" -eq 0 ]]; then
  exit 0
fi

# Mark as notified for this session
touch "$notified_file"

# Inject context for the AI via stdout
cat <<'CONTEXT'
[devflow watchdog] Stale sensitive files detected after a recent merge to main.
Pending mechanical fixes and/or semantic reviews are queued.
Run /devflow:check-sensitive to review and apply fixes.
CONTEXT

exit 0
