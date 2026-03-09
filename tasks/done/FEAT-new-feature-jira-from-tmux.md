---
id: FEAT-new-feature-jira-from-tmux
title: "New Feature Skill: Auto-Detect Ticket ID from TMUX/Agent-Deck Session"
priority: P1
category: feature
status: done
depends_on: []
estimated_effort: S
files_to_touch:
  - devflow-plugin/commands/new-feature.md
---

# New Feature Skill: Auto-Detect Ticket ID from TMUX/Agent-Deck Session

## Context

The `/new-feature` skill accepts `$ARGUMENTS` where the first word is a ticket ID (e.g. `MES-3716`). But when launched from agent-deck, the ticket ID is often already embedded in the TMUX session name.

Agent-deck session names follow the pattern `agentdeck_<SESSION-NAME>_<HASH>`. Users typically name sessions after the ticket (e.g. `MES-3678`, `Discovery-MES-3716`).

## Discovery

```bash
# Get the tmux session name from inside the session:
tmux display-message -p '#{session_name}'
# → agentdeck_MES-3678_1d588108

# Extract ticket ID:
echo "$session_name" | grep -oE '[A-Z]+-[0-9]+' | head -1
# → MES-3678
```

- `AGENTDECK_INSTANCE_ID` env var is set inside sessions
- `CLAUDE_SESSION_ID` is also set by agent-deck
- No explicit `AGENTDECK_SESSION_NAME` env var — must use `tmux display-message`

## Desired Outcome

When `/new-feature` is invoked WITHOUT a ticket ID argument:

1. Check if running inside a TMUX session (`$TMUX` env var or `tmux display-message`)
2. Get the session name via `tmux display-message -p '#{session_name}'`
3. Extract a ticket pattern (`[A-Z]+-[0-9]+`) from the session name
4. If found, suggest the ticket ID to the user: "Detected ticket **MES-3678** from session name. Using this?"
5. If confirmed (or if no explicit override), use it as `TICKET_ID`
6. If no ticket found in session name, proceed as before (prompt or skip)

## Implementation

Update `devflow-plugin/commands/new-feature.md`:

- Add a new step before the current "Parse arguments" step
- The new step: "Detect ticket from environment" — runs ONLY when no ticket ID was provided in `$ARGUMENTS`
- Detection order:
  1. `$ARGUMENTS` (explicit, always wins)
  2. TMUX session name (auto-detected)
  3. No ticket (proceed without)

## Acceptance Criteria

- [ ] When launched with `$ARGUMENTS` containing a ticket ID, behavior unchanged
- [ ] When launched without arguments inside an agent-deck session, ticket is auto-detected
- [ ] When launched without arguments outside TMUX, no error — proceeds normally
- [ ] User is shown the detected ticket and can confirm or override
