---
id: FEAT-context-compaction-skill
title: "Context Compaction Skill"
priority: P2
category: features
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - devflow-plugin/commands/compact.md
  - lib/compact.sh
  - skills/registry.json
---

# Context Compaction Skill

## Context

Users often ask agents to "compact the context" or "summarize and start fresh" when context windows get large. Currently this is handled ad-hoc — the agent either summarizes inline (losing detail) or the user manually starts a new session (losing everything). Neither approach is optimal. A structured compaction workflow can preserve critical context while reducing token usage.

## Problem Statement

1. **In-place compaction is lossy**: Summarizing context mid-session discards nuance, edge cases, and partial progress that may matter later
2. **Starting fresh loses everything**: New sessions start with zero context unless the user manually provides a brief
3. **No middle ground exists**: There's no workflow to transfer context between sessions efficiently — users either over-compact or over-retain
4. **Hindsight is underutilized**: Persistent memory could serve as the transfer layer between sessions, but there's no automation around this

## Desired Outcome

- A `/devflow:compact` command that presents three clear options for context management
- Each option has well-defined tradeoffs (speed vs. fidelity vs. cost)
- The "new session with handoff" option creates a structured handoff document that a new session can pick up seamlessly
- Hindsight is used as the durable memory layer for learnings that outlive the current task

## Implementation Guide

### Step 1: Create the `/devflow:compact` skill command

Create `devflow-plugin/commands/compact.md`:

````markdown
---
name: compact
description: Manage context size with smart compaction or session handoff
---

# Context Compaction

## Step 1: Assess Context Size

Estimate current context usage:

- Count approximate tokens based on conversation length
- Identify the largest context contributors (long file reads, verbose tool outputs)
- Report: "Estimated context: ~Xk tokens (Y% of window)"

## Step 2: Present Options

Present three options to the user:

### Option A: Compact in-place

- Summarize current context, continue in same session
- **Pro**: No session switch, fastest
- **Con**: Lossy — nuance and partial work may be lost
- **Best for**: Simple tasks, exploratory work

### Option B: New session with handoff (Recommended for complex tasks)

- Create a structured handoff, transfer via Hindsight + markdown file
- **Pro**: Full fidelity, organized transfer, persistent learnings saved
- **Con**: Requires starting a new session
- **Best for**: Multi-step features, debugging sessions, long implementations

### Option C: New session with memory only

- Start fresh, rely on Hindsight recall for context
- **Pro**: Cheapest, fastest new session
- **Con**: Only previously-retained memories transfer — current session context is lost
- **Best for**: Switching to a different task, session was mostly exploration

Ask: "Which option? [A/B/C]"

## Step 3: Execute chosen option

### If Option A (Compact in-place):

1. Summarize the current session into key points:
   - Current goal and progress
   - Key decisions made
   - Files touched and their state
   - Remaining work
2. Present summary to user for review
3. Instruct: "Context has been compacted. Previous details are summarized above."

### If Option B (Handoff):

1. **Retain persistent learnings to Hindsight:**
   - Architectural discoveries
   - Bug root causes
   - Convention corrections
   - Integration gotchas
     Each as a separate `retain()` call with appropriate tags.

2. **Create handoff markdown file:**
   Write to `~/.devflow/handoffs/<timestamp>-<short-description>.md`:
   ```markdown
   # Session Handoff: <goal>

   ## Date: <timestamp>

   ## Goal

   <What we're trying to accomplish>

   ## Progress

   - [x] Completed steps
   - [ ] Remaining steps

   ## Key Decisions

   - Decision 1: rationale
   - Decision 2: rationale

   ## Files Touched

   - path/to/file.ts — what was changed and why

   ## Current State

   <Where we left off, what to do next>

   ## Test Status

   <Which tests pass/fail, what needs testing>

   ## Notes

   <Anything else the next session needs to know>
   ```
````

3. **Output the handoff path and suggest:**

   ```
   Handoff saved to: ~/.devflow/handoffs/<file>.md

   Start a new session with:
     claude --resume "Continue from handoff: ~/.devflow/handoffs/<file>.md"

   Or manually:
     1. Start new session
     2. Paste: "Resume work from ~/.devflow/handoffs/<file>.md"
   ```

### If Option C (Memory only):

1. Suggest running `/devflow:learn` first to capture any session learnings
2. Output: "Start a new session. Use recall('<project>: <topic>') to retrieve relevant context."

````

### Step 2: Create CLI-side handoff support

Create `lib/compact.sh` for any shell-side operations:

```bash
#!/usr/bin/env bash

HANDOFF_DIR="${HOME}/.devflow/handoffs"

ensure_handoff_dir() {
  mkdir -p "$HANDOFF_DIR"
}

list_handoffs() {
  if [[ -d "$HANDOFF_DIR" ]]; then
    ls -1t "$HANDOFF_DIR"/*.md 2>/dev/null | head -10
  else
    echo "No handoffs found."
  fi
}

clean_old_handoffs() {
  local days="${1:-7}"
  find "$HANDOFF_DIR" -name "*.md" -mtime "+${days}" -delete 2>/dev/null
  echo "Cleaned handoffs older than ${days} days."
}
````

Optionally add `devflow handoffs` as a CLI command to list and manage handoff files.

### Step 3: Update skills registry

Add to `skills/registry.json`:

```json
{
  "name": "compact",
  "path": "devflow-plugin/commands/compact.md",
  "description": "Manage context size with smart compaction or session handoff",
  "category": "workflow"
}
```

## Acceptance Criteria

- [ ] `/devflow:compact` is available as a command and listed in the skill registry
- [ ] Running it shows estimated context size (approximate token count)
- [ ] Three options (A, B, C) are presented with clear tradeoffs
- [ ] Option A produces a concise summary of current session state
- [ ] Option B retains learnings to Hindsight AND creates a handoff markdown file
- [ ] Handoff file is written to `~/.devflow/handoffs/` with a descriptive filename
- [ ] Handoff file contains: goal, progress, key decisions, files touched, current state, test status
- [ ] Option B outputs the handoff file path and instructions for resuming
- [ ] Option C suggests running `/devflow:learn` first and provides recall guidance
- [ ] `~/.devflow/handoffs/` directory is created automatically if it doesn't exist
- [ ] Old handoffs can be cleaned up (either manually or via `clean_old_handoffs`)

## Technical Notes

- Token estimation is approximate — count conversation turns × estimated tokens per turn, or use character count ÷ 4 as a rough estimate
- The handoff file should be human-readable AND agent-readable — it will be consumed by both
- Hindsight `retain` calls in Option B are for DURABLE learnings (survive beyond this task). The handoff file is for TASK-SPECIFIC state (ephemeral)
- Consider adding a `devflow resume <handoff-file>` CLI command that starts a new Claude Code session with the handoff file as initial context
- The handoff filename format: `<unix-timestamp>-<slugified-goal>.md` (e.g., `1709558400-fix-auth-middleware.md`)
- Handoff files should NOT contain secrets, credentials, or full file contents — only references and summaries

## Verification

```bash
# 1. Verify command availability
# In a Claude Code session, run /devflow:compact
# Expect: Context estimate and three options presented

# 2. Test Option A (in-place compaction)
# After a long session, choose Option A
# Expect: Concise summary, session continues

# 3. Test Option B (handoff)
# Choose Option B
# Expect: Hindsight retain calls for learnings
# Expect: Handoff file created at ~/.devflow/handoffs/<file>.md
# Expect: File contains all required sections
# Verify: cat ~/.devflow/handoffs/<most-recent>.md

# 4. Test Option B handoff consumption
# Start a new session, paste the handoff file path
# Expect: Agent recalls Hindsight memories AND reads handoff file
# Expect: Agent can continue work from where previous session left off

# 5. Test Option C (memory only)
# Choose Option C
# Expect: Suggestion to run /devflow:learn, then recall instructions

# 6. Verify handoff cleanup
# Run: clean_old_handoffs 0  (or devflow handoffs clean)
# Expect: All handoff files deleted
```
