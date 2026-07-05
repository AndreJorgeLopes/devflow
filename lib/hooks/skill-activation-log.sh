#!/usr/bin/env bash
# devflow/lib/hooks/skill-activation-log.sh
# Claude Code PreToolUse hook (matcher: Skill) — the WRITE side of trace-review's
# attribution enrichment. Appends one {session_id, ts, skill} row to a local JSONL
# sidecar every time the Skill tool is invoked, so lib/trace-review.py rung 3 can
# attribute a session's traces to the skill even when Claude Code emitted no
# skill_name span. It is the deterministic fallback for the fact that Claude Code
# does not stamp skill_name on most interaction/tool spans.
#
# Why PreToolUse:Skill (precision over recall): tool_input.skill is the EXACT skill
# name at the moment it runs. Capturing here (not from UserPromptSubmit) avoids
# recording non-skill slash commands (/compact, /clear, ...) that would mis-attribute
# unrelated traces. A missed row just leaves a trace (unattributed); a wrong row
# would corrupt a real skill's numbers.
#
# Protocol (PreToolUse):
#   Always exit 0 — this hook is observational and MUST never block the tool call.
#   stdout is ignored by design.
#
# Privacy/footprint: writes only session_id + UTC timestamp + skill name. No prompt
# text, no args, no secrets. Sidecar path is $TRACE_REVIEW_SIDECAR (default
# ~/.devflow/skill-activations.jsonl); the read path uses the same env default.

set -euo pipefail

payload="$(cat)"

# All parsing + the append happen in Python so a malformed payload cannot abort the
# tool call (|| true). stdin, not argv: the payload can be large and contain quotes.
printf '%s' "$payload" | python3 -c '
import sys, json, os, datetime

try:
    p = json.load(sys.stdin)
except Exception:
    sys.exit(0)

# Defensive: this hook is registered with matcher "Skill", but re-check so a
# misconfigured settings.json (no/loose matcher) never logs non-Skill tools.
if p.get("tool_name") != "Skill":
    sys.exit(0)

ti = p.get("tool_input") or {}
skill = ti.get("skill") or ti.get("command")
session_id = p.get("session_id")
if not skill or not session_id:
    sys.exit(0)

row = {
    "session_id": session_id,
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "skill": skill,
}
path = os.environ.get(
    "TRACE_REVIEW_SIDECAR",
    os.path.join(os.path.expanduser("~"), ".devflow", "skill-activations.jsonl"),
)
try:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(row) + "\n")
except OSError:
    pass  # never fail the tool call over a logging write
' || true

exit 0
