#!/usr/bin/env bash
# devflow/lib/hooks/stop-finish-prompt.sh
# Claude Code Stop hook — stub for future stop-hook needs.
#
# The finish-feature prompting logic was removed (ARCH-stop-hook-finish-feature-removal)
# because the stop hook fires on ALL agent stops including subagents, reviews, etc.
# Finish-feature transition is now handled at the skill level (new-feature.md).
#
# Protocol: exit 0 = allow stop, exit 2 = block stop and re-activate agent

set -euo pipefail

# No-op — allow all stops
exit 0
