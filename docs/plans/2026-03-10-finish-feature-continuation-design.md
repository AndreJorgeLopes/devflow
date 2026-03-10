# Finish-Feature Post-PR Continuation & Auto-Memory Migration

## Problem

Two issues affecting the devflow finish-feature workflow:

1. **Stop hook breaks post-PR flow.** After `finish-feature` creates a PR/MR (step 6), Claude tries to stop. The Stop hook fires because the branch has unmerged commits ahead of main. Claude sees `Stop hook error: [INTENTIONAL "ERROR"] Unmerged work detected` and interprets it as "nothing to do" — skipping steps 7-9 (retain learnings, summary, worktree cleanup).

2. **Auto-memory duplicates Hindsight.** Claude Code's built-in auto-memory system (`~/.claude/projects/.../memory/MEMORY.md`) stores project knowledge in parallel with Hindsight, despite CLAUDE.md explicitly instructing agents to use Hindsight. Valuable memories are stranded in auto-memory files instead of being searchable via Hindsight.

## Design

### Architecture: Layered Hook Strategy

Replace the single Stop hook approach with a 3-layer strategy that provides clean context injection after PR creation, a smarter safety net, and stronger skill instructions.

```
PR created (step 6)
       │
       ▼
┌─────────────────────────┐
│  Layer 1: PostToolUse   │  ← fires immediately after `gh pr create` / `glab mr create`
│  post-pr-continue.sh    │  ← exit 2 + stderr = clean context (no "error:" prefix)
│  "Continue steps 7-9"   │
└─────────────────────────┘
       │
       ▼
  Agent continues steps 7-9
       │
       ▼
  Agent tries to stop
       │
       ▼
┌─────────────────────────┐
│  Layer 2: Stop hook     │  ← detects PR/MR exists for branch
│  stop-finish-prompt.sh  │  ← exit 0 (allow stop — PostToolUse handled it)
│  (updated)              │
└─────────────────────────┘
       │
       ▼
  Agent stops cleanly (no "error:" shown)
```

**Fallback path** (finish-feature never invoked):
```
Agent tries to stop on feature branch
       │
       ▼
┌─────────────────────────┐
│  Layer 2: Stop hook     │  ← no PR/MR found
│  stop-finish-prompt.sh  │  ← exit 2 (block stop, show "error:" — acceptable here)
│  "Run finish-feature"   │
└─────────────────────────┘
```

---

### Layer 1: PostToolUse Hook — `post-pr-continue.sh`

**File:** `lib/hooks/post-pr-continue.sh`

**Purpose:** After a PR/MR is created via Bash, inject a clean continuation prompt telling the agent to complete the remaining finish-feature steps.

**Behavior:**
1. Read PostToolUse JSON payload from stdin
2. Extract `tool_name` and `tool_input.command`
3. If `tool_name != "Bash"` → exit 0 (silent)
4. If command does not contain `gh pr create` or `glab mr create` → exit 0
5. If matched → exit 2 with stderr message:

```
[devflow] PR/MR created successfully. The finish-feature flow is not complete yet.
Continue with the remaining steps:
- Retain session learnings via Hindsight (architecture decisions, gotchas, bug fixes)
- Present the feature completion summary to the user
- Offer worktree cleanup options
Do NOT stop until all remaining finish-feature steps are complete.
```

**Registration in `~/.claude/settings.json`:**
```json
{
  "PostToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "/Users/andrejorgelopes/dev/devflow/lib/hooks/post-pr-continue.sh"
        }
      ]
    }
  ]
}
```

**Registration in `lib/init.sh`:** Add PostToolUse hook registration alongside existing Stop and UserPromptSubmit hooks.

---

### Layer 2: Stop Hook Update — `stop-finish-prompt.sh`

**File:** `lib/hooks/stop-finish-prompt.sh` (modify existing)

**Changes:** After the existing `stop_hook_active` and branch checks, add PR/MR detection before deciding to block. Source `lib/utils.sh` for `detect_vcs_provider`.

**Logic:**
1. Existing checks (stop_hook_active, feature branch, commits ahead) — unchanged
2. **New:** Detect VCS provider and check if PR/MR exists:
   - GitHub: `gh pr list --head "$current_branch" --json number --jq 'length'`
   - GitLab: `glab mr list --source-branch "$current_branch" 2>/dev/null | grep -c .`
3. If PR/MR exists → exit 0 (allow stop — work is submitted)
4. If no PR/MR → exit 2 with current message (block stop)

**Pseudocode for the new section:**
```bash
# Source utils for VCS detection
source "$(dirname "$0")/../utils.sh"

provider="$(detect_vcs_provider)"
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
```

---

### Layer 3: Finish-Feature Skill Update

**File:** `devflow-plugin/commands/finish-feature.md`

**Changes:** Add an explicit instruction after step 6 (PR creation) to prevent premature stopping.

Add between steps 6 and 7:
```markdown
> **CRITICAL: Do NOT stop after creating the PR/MR.** Steps 7-9 below are mandatory.
> The feature is not complete until you have retained learnings, presented the summary,
> and offered worktree cleanup. Continue immediately.
```

No other skill changes needed — the current steps 7-9 already cover retain learnings, summary, and worktree cleanup.

---

### Auto-Memory Migration to Hindsight

**Files to migrate:**

1. `~/.claude/projects/-Users-andrejorgelopes-dev-aircall-messaging/memory/MEMORY.md`
2. `~/.claude/projects/-Users-andrejorgelopes-dev-aircall-messaging/memory/workflow-preferences.md`
3. `~/.claude/projects/-Users-andrejorgelopes--fulcrum-worktrees-messaging-project-connections-visualization-7vw6/memory/MEMORY.md`

**Memories to retain in Hindsight** (extracted from files):

| Memory | Tags |
|--------|------|
| Messaging project uses GitLab — `glab` CLI for MR creation, templates in `.gitlab/merge_request_templates/` | `messaging`, `convention` |
| Never include "Generated with Claude Code" attribution in MRs | `messaging`, `convention` |
| Never create draft MRs — always normal MRs | `messaging`, `convention` |
| NEVER create Jira issues directly — always preview and confirm. No "yes, don't ask again" | `messaging`, `convention`, `gotcha` |
| Architectural decisions: present pros/cons, ask "decide now or defer to team?" | `messaging`, `convention` |
| Jira Atlassian Cloud ID: `187a5cac-08ba-47c4-af5a-8abecab302da` | `messaging`, `pattern` |
| Messaging tech stack: TypeScript, AWS Lambda, Node.js 22, Middy, Aurora MySQL, DynamoDB, SQS | `messaging`, `architecture` |
| Clean/Hexagonal architecture: application/ → domain/ → infrastructure/ | `messaging`, `architecture` |
| MAIA AI agent pipeline: Inbound → SQS Queue A → event-consumers → SQS FIFO → AI worker → Azure OpenAI | `messaging`, `architecture` |
| Team uses kanban (no sprints), 6-stage workflow | `messaging`, `convention` |

**After migration:** Clear the auto-memory files to prevent confusion. The memories now live in Hindsight where they're searchable across sessions.

---

### CLAUDE.md Update — Hindsight Priority

**File:** `~/.claude/CLAUDE.md`

**Add to the "Agent Memory (Hindsight)" section:**

```markdown
### Auto-Memory Avoidance

Do NOT use Claude Code's built-in auto-memory system (`~/.claude/projects/.../memory/MEMORY.md`)
for storing project knowledge, preferences, or learnings. All persistent memory MUST go through
Hindsight via `retain`. The auto-memory files are reserved for minimal session-level notes only.

If you discover project-relevant information that should persist, use `retain` — never write to
the auto-memory MEMORY.md files.
```

---

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `lib/hooks/post-pr-continue.sh` | Create | PostToolUse hook for post-PR continuation |
| `lib/hooks/stop-finish-prompt.sh` | Modify | Add PR/MR existence check, exit 0 when PR exists |
| `lib/init.sh` | Modify | Register PostToolUse hook in settings.json |
| `devflow-plugin/commands/finish-feature.md` | Modify | Add "do not stop" instruction after PR creation |
| `~/.claude/CLAUDE.md` | Modify | Add auto-memory avoidance instruction |
| `~/.claude/settings.json` | Modified by init | PostToolUse hook registration |

## Testing

1. **PostToolUse hook:** Run a Bash command containing `gh pr create` in a test session → verify stderr message appears cleanly (no "error:" prefix)
2. **Stop hook PR detection:** On a branch with an existing PR, trigger stop → verify hook exits 0 (no blocking)
3. **Stop hook fallback:** On a branch with no PR, trigger stop → verify hook exits 2 (blocks, shows finish-feature prompt)
4. **End-to-end:** Run full finish-feature flow → verify steps 7-9 complete after PR creation without hook interference
5. **Hindsight migration:** Verify migrated memories are recallable via `recall("messaging: MR conventions")`

## Risks

- **PostToolUse latency:** Hook fires for every Bash tool call but exits immediately (exit 0) for non-PR commands. Only the command string check adds ~1ms. PR detection in the Stop hook adds ~1-2s but only fires when the agent tries to stop on a feature branch.
- **gh/glab not installed:** PR detection in the Stop hook falls back to the current behavior (exit 2) if the CLI tool is missing or errors.
- **Auto-memory re-creation:** Claude Code may continue writing to auto-memory files despite CLAUDE.md instructions. The instruction reduces frequency but may not eliminate it entirely. Monitor and clear periodically if needed.
