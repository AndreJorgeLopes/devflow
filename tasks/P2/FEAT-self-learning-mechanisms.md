---
id: FEAT-self-learning-mechanisms
title: "Self-Learning Mechanisms (Agent Memory Hooks)"
priority: P2
category: features
status: open
depends_on: []
estimated_effort: L
files_to_touch:
  - devflow-plugin/hooks/hooks.json
  - devflow-plugin/commands/learn.md
  - skills/registry.json
---

# Self-Learning Mechanisms (Agent Memory Hooks)

## Context

Agents should automatically learn from mistakes and retain corrections without manual intervention. Currently, Hindsight memory is only populated through explicit `retain` calls or manual seeding. This means valuable learnings — error patterns, user corrections, session discoveries — are lost between sessions unless the user or agent remembers to save them.

Inspired by the approach described in [this Reddit post](https://www.reddit.com/r/ClaudeCode/comments/1reib80/how_i_went_from_vibe_coding_to_shipping_a/), which emphasizes CLAUDE.md-based learning. We already have that via our CLAUDE.md template — this ticket adds AUTOMATIC learning on top through Claude Code's hook system.

## Problem Statement

1. When tools fail, the error context is lost after the session ends — the same mistakes recur in future sessions
2. When users correct the agent ("actually, we do X not Y"), the correction exists only in conversation context and is forgotten next session
3. End-of-session learnings (architectural discoveries, integration gotchas, performance findings) are not systematically captured
4. There is no automated pipeline from "agent experience" to "persistent memory"

## Desired Outcome

- Claude Code hooks automatically detect learning opportunities (tool failures, user corrections, session end)
- A `/devflow:learn` skill provides on-demand session reflection and memory retention
- The hooks work WITHIN the existing Hindsight + Claude Code architecture — no new tools or flows are introduced
- Retained memories are tagged appropriately for future `recall` relevance

## Implementation Guide

### Step 1: Create hooks.json for Claude Code plugin

Create `devflow-plugin/hooks/hooks.json`:

```json
{
  "hooks": [
    {
      "type": "PostToolUse",
      "command": "echo 'DEVFLOW_HOOK: Tool execution completed. If this tool failed or returned an error, retain the error context and root cause analysis to Hindsight with tags [bugfix, gotcha]. Use: retain(\"<project>: ERROR - <tool> failed with <error>. Root cause: <analysis>\", tags=[\"bugfix\", \"gotcha\"])'"
    },
    {
      "type": "UserPromptSubmit",
      "command": "echo 'DEVFLOW_HOOK: Check if the user message contains correction patterns (actually, no that is wrong, I told you, don't do that, stop doing, wrong, incorrect). If it does, retain the correction to Hindsight: retain(\"<project>: CORRECTION - <what was wrong> → <what is correct>\", tags=[\"correction\", \"convention\"])'"
    },
    {
      "type": "Stop",
      "command": "echo 'DEVFLOW_HOOK: Session ending. Consider running /devflow:learn to capture session learnings before context is lost.'"
    }
  ]
}
```

**Important design notes on hooks:**

- The hooks output instructional text that the agent processes — they don't execute retain calls directly (hooks run shell commands, not agent actions)
- The PostToolUse hook fires on EVERY tool use — the agent must filter to only act on failures
- The UserPromptSubmit hook must pattern-match conservatively to avoid false positives
- The Stop hook is a reminder, not an automatic action — the user decides whether to run `/devflow:learn`

### Step 2: Create the `/devflow:learn` skill command

Create `devflow-plugin/commands/learn.md`:

```markdown
---
name: learn
description: Review current session, identify learnings, and retain them to Hindsight
---

# Session Learning Extraction

## What You Must Do

1. **Review the session**: Look back through this conversation and identify:
   - Mistakes made and their root causes
   - Corrections from the user (explicit or implicit)
   - Architectural or codebase discoveries
   - Integration gotchas (API quirks, config issues, env specifics)
   - Performance findings
   - Non-obvious patterns or conventions discovered

2. **Categorize each learning** with appropriate tags:
   - `bugfix` — Error encountered and how it was resolved
   - `gotcha` — Non-obvious behavior that caused confusion
   - `correction` — User corrected the agent's assumption or approach
   - `convention` — Project-specific convention discovered
   - `architecture` — Structural insight about the codebase
   - `pattern` — Recurring pattern worth remembering
   - `decision` — Decision made with rationale worth preserving

3. **Present learnings to the user** before retaining:
   Show each learning as:
```

[tag] Title
Content (1-2 sentences)

```
Ask: "Retain these N learnings to Hindsight? [Y/n/edit]"

4. **Retain confirmed learnings**:
For each confirmed learning, call:
```

retain("<project>: <concise summary>", tags=["<project>", "<primary-tag>", "<secondary-tag>"])

```

5. **Report summary**:
```

Retained N learnings to Hindsight:

- 2 bugfixes
- 1 convention
- 3 gotchas

```

## Rules
- Keep memories atomic — one concept per retain call
- Always prefix with the project name
- Don't retain obvious things (language syntax, standard library)
- DO retain project-specific things (custom patterns, team preferences, past mistakes)
- If no learnings are identified, say so honestly — don't fabricate
```

### Step 3: Update skills registry

Add the new command to `skills/registry.json`:

```json
{
  "name": "learn",
  "path": "devflow-plugin/commands/learn.md",
  "description": "Review current session and retain learnings to Hindsight memory",
  "category": "memory"
}
```

### Step 4: Test hook integration

Verify that Claude Code loads hooks from `devflow-plugin/hooks/hooks.json` when the plugin is active. The hooks should appear in the agent's behavior without any additional configuration.

## Acceptance Criteria

- [ ] `hooks.json` is created with PostToolUse, UserPromptSubmit, and Stop hooks
- [ ] PostToolUse hook triggers after tool executions — agent retains error context only when tools actually fail
- [ ] UserPromptSubmit hook detects correction patterns in user messages and retains corrections
- [ ] Stop hook reminds the agent (and user) to run `/devflow:learn` before session ends
- [ ] `/devflow:learn` command is available and listed in skill registry
- [ ] Running `/devflow:learn` reviews the session and presents categorized learnings
- [ ] User can confirm, reject, or edit learnings before they are retained
- [ ] Retained memories use correct tags and project prefix
- [ ] Hooks do NOT break existing tool execution or session flow
- [ ] False positive rate on correction detection is acceptably low (no retain on casual "actually" usage)
- [ ] Memories retained via hooks can be recalled in subsequent sessions via `recall("<project>: ...")`

## Technical Notes

- Claude Code hooks documentation: Check `https://claude.ai/docs` for the hooks API spec
- Hooks run shell commands whose stdout is presented to the agent — they are instructional, not imperative
- The PostToolUse hook fires for EVERY tool call (Read, Write, Bash, etc.) — the agent must only act on failures to avoid noise
- Correction pattern matching should be conservative. Patterns to match: "actually, we", "no, that's wrong", "I told you to", "don't do that", "stop doing", "that's incorrect", "wrong approach". Patterns to SKIP: "actually" used casually mid-sentence, "no" as part of a different context
- Consider rate-limiting retains — if 5 tools fail in a row with the same error, retain once, not 5 times
- The `/devflow:learn` skill is a SOFT skill (flexible) — the agent adapts the depth of reflection to the session's complexity

## Verification

```bash
# 1. Verify hooks.json is loaded
# Start a Claude Code session with the devflow plugin active
# Run a command that fails (e.g., reference a nonexistent file)
# Check: Does the agent mention retaining the error to Hindsight?

# 2. Verify correction detection
# In a session, type: "Actually, that's wrong. We use yarn, not npm."
# Check: Does the agent retain a correction memory?

# 3. Verify /devflow:learn
# After a productive session, run /devflow:learn
# Check: Does it present categorized learnings?
# Check: Does it ask for confirmation before retaining?
# Check: After confirming, are memories queryable via recall?

# 4. Verify no false positives
# Type: "I actually like this approach"
# Check: Agent should NOT retain this as a correction

# 5. Verify Stop hook
# End a session (Ctrl+C or /exit)
# Check: Agent mentions /devflow:learn before closing
```
