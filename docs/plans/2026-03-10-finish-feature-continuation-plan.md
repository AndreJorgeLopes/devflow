# Finish-Feature Post-PR Continuation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the finish-feature flow so steps 7-9 (retain learnings, summary, worktree cleanup) reliably execute after PR/MR creation, and migrate stranded auto-memory files to Hindsight.

**Architecture:** A 3-layer hook strategy — PostToolUse hook injects clean continuation context after PR creation, Stop hook detects existing PRs and allows stop, finish-feature skill adds explicit "don't stop" instruction. Plus auto-memory migration to Hindsight and CLAUDE.md update.

**Tech Stack:** Bash (hooks), Markdown (skill), Python (init.sh hook registration), Hindsight MCP (memory migration)

---

## Chunk 1: Hook Implementation

### Task 1: Create PostToolUse hook — `post-pr-continue.sh`

**Files:**
- Create: `lib/hooks/post-pr-continue.sh`

- [ ] **Step 1: Create the hook script**

Create `lib/hooks/post-pr-continue.sh`:

```bash
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
```

- [ ] **Step 2: Make the hook executable**

Run: `chmod +x lib/hooks/post-pr-continue.sh`

- [ ] **Step 3: Verify the hook works with a mock payload**

Run:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test --body test"}}' | bash lib/hooks/post-pr-continue.sh; echo "exit: $?"
```
Expected: stderr shows the continuation message, exit code 2.

Run:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash lib/hooks/post-pr-continue.sh; echo "exit: $?"
```
Expected: no output, exit code 0.

Run:
```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test"}}' | bash lib/hooks/post-pr-continue.sh; echo "exit: $?"
```
Expected: no output, exit code 0.

- [ ] **Step 4: Commit**

```bash
git add lib/hooks/post-pr-continue.sh
git commit -m "feat(hooks): add PostToolUse hook for post-PR continuation prompt"
```

---

### Task 2: Update Stop hook — PR/MR detection

**Files:**
- Modify: `lib/hooks/stop-finish-prompt.sh`

- [ ] **Step 1: Add PR/MR existence check to the stop hook**

Insert the PR detection logic after the `commits_ahead` check (after line 35) and before the final stderr + exit 2 (lines 37-40). The new section sources `lib/utils.sh` for VCS detection and checks whether a PR/MR already exists for the current branch.

Replace the entire file with:

```bash
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

# No PR/MR found — block stop and prompt for finish-feature
echo '[INTENTIONAL "ERROR"] Unmerged work detected — prompting for finish-feature flow.' >&2

exit 2
```

- [ ] **Step 2: Verify PR detection works (on a branch with an existing PR)**

Run (from the devflow repo, on `feat/review-pr-description` which has merged PRs):
```bash
echo '{}' | bash lib/hooks/stop-finish-prompt.sh; echo "exit: $?"
```
Expected: exit code 0 (PR exists, allow stop, no output).

- [ ] **Step 3: Verify fallback works (simulate no PR)**

Run (temporarily test with a non-existent branch name — manually check the gh command):
```bash
gh pr list --head "nonexistent-branch-xyz" --json number --jq 'length' 2>/dev/null || echo "0"
```
Expected: output `0`.

- [ ] **Step 4: Commit**

```bash
git add lib/hooks/stop-finish-prompt.sh
git commit -m "feat(hooks): add PR/MR detection to stop hook — allow stop when PR exists"
```

---

### Task 3: Register PostToolUse hook in `init.sh`

**Files:**
- Modify: `lib/init.sh` (the Python hook registration block, around lines 334-356)

- [ ] **Step 1: Add PostToolUse hook registration**

In `lib/init.sh`, inside the Python code block that registers hooks (after the UserPromptSubmit registration block at line 355), add the PostToolUse hook registration. Insert before the `if changed:` line:

```python
# PostToolUse hook — post-PR continuation prompt
ptu_hooks = hooks.setdefault('PostToolUse', [])
ptu_cmd = hook_root + '/lib/hooks/post-pr-continue.sh'
if not any('post-pr-continue' in str(entry) for entry in ptu_hooks):
    ptu_hooks.append({'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': ptu_cmd}]})
    changed = True
    print('Added PostToolUse hook: post-pr-continue')
else:
    print('Skip: PostToolUse hook already registered')
```

- [ ] **Step 2: Verify init.sh runs without errors**

Run:
```bash
bash -n lib/init.sh
```
Expected: no syntax errors.

- [ ] **Step 3: Commit**

```bash
git add lib/init.sh
git commit -m "feat(init): register PostToolUse hook for post-PR continuation"
```

---

### Task 4: Update finish-feature skill

**Files:**
- Modify: `devflow-plugin/commands/finish-feature.md`

- [ ] **Step 1: Add "do not stop" instruction after step 6**

In `devflow-plugin/commands/finish-feature.md`, after line 125 (`Present the PR/MR URL to the user.`), add:

```markdown

   > **CRITICAL: Do NOT stop after creating the PR/MR.** Steps 7-9 below are mandatory.
   > The feature is not complete until you have retained learnings, presented the summary,
   > and offered worktree cleanup. Continue immediately.
```

- [ ] **Step 2: Commit**

```bash
git add devflow-plugin/commands/finish-feature.md
git commit -m "feat(skills): add explicit continuation instruction after PR creation in finish-feature"
```

---

## Chunk 2: Auto-Memory Migration & CLAUDE.md

### Task 5: Migrate auto-memory files to Hindsight

**No files changed** — this task uses Hindsight MCP tools only.

- [ ] **Step 1: Retain messaging project conventions**

Use Hindsight `retain` for each of these memories:

1. `retain("messaging: GitLab project — use glab CLI for MR creation. Templates in .gitlab/merge_request_templates/ (Feature.md, Default.md, Bugfix.md, Carrier-Integration.md, Security.md, Refactoring.md). Never include 'Generated with Claude Code' attribution. Never create draft MRs — always normal MRs.", tags=["messaging", "convention"])`

2. `retain("messaging: NEVER create Jira issues directly — always show a preview first and ask for explicit confirmation. Never allow 'yes, and don't ask again' for Jira issue creation — always confirm each time.", tags=["messaging", "convention", "gotcha"])`

3. `retain("messaging: Architectural decision process — always present pros and cons with concrete impacts (performance, complexity, consistency). Ask 'Decide now or discuss with team first?' If deferred, continue where possible and leave TODOs. Deferred answers can be: a decision, 'not needed anymore', or 'we went with a different fix'.", tags=["messaging", "convention"])`

4. `retain("messaging: Jira Atlassian Cloud ID is 187a5cac-08ba-47c4-af5a-8abecab302da (aircall-product.atlassian.net)", tags=["messaging", "pattern"])`

5. `retain("messaging: Tech stack — TypeScript + AWS Lambda + Node.js 22 + Middy middleware. Aurora MySQL (transactional) + DynamoDB (counters/cache) + SQS (async). Carriers: Twilio, Bandwidth, Legos, Symbio, WhatsApp/Meta (+ TCR for A2P). Clean/Hexagonal architecture: application/ → domain/ → infrastructure/. Handler factories: endpointHandlerFactory (HTTP) and sqsHandlerFactory (SQS).", tags=["messaging", "architecture"])`

6. `retain("messaging: MAIA AI agent pipeline — Multi-repo: messaging (Lambda/SAM) → messaging-ai-agent (NestJS/K8s) → messaging-extension (React) → internal-api (AppSync). Pipeline: Inbound msg → SQS Queue A → event-consumers → SQS FIFO Queue B (per-conversation) → AI worker → Azure OpenAI → reply. Trinity Model: Role + Tone + Goal. messaging-ai-agent uses: pnpm, Turbo, Biome, NestJS, K8s, ArgoCD, Valkey, PostgreSQL+Drizzle, Vitest.", tags=["messaging", "architecture"])`

7. `retain("messaging: Team uses kanban (no sprints) with 6-stage workflow. Team members (March 2026): Agustin BAUER (infra), Filipe Estacio (AI/GraphQL), Pauline ROUSSET (Group Messaging API), Alessandro OLIVERI (AI LLM), Ajay Singh (webhooks), Pournima TELE (frontend), Bogdan Pintican / Cristian Lica (contractors).", tags=["messaging", "convention"])`

- [ ] **Step 2: Verify migration with recall**

Run: `recall("messaging: MR conventions")` — should return the GitLab/glab memory.
Run: `recall("messaging: Jira issue creation")` — should return the "never create directly" memory.

- [ ] **Step 3: Clear the auto-memory files**

Clear (but don't delete) the 3 auto-memory files to prevent confusion:

1. Write `# Migrated to Hindsight (2026-03-10)\n` to `~/.claude/projects/-Users-andrejorgelopes-dev-aircall-messaging/memory/MEMORY.md`
2. Write `# Migrated to Hindsight (2026-03-10)\n` to `~/.claude/projects/-Users-andrejorgelopes-dev-aircall-messaging/memory/workflow-preferences.md`
3. Write `# Migrated to Hindsight (2026-03-10)\n` to `~/.claude/projects/-Users-andrejorgelopes--fulcrum-worktrees-messaging-project-connections-visualization-7vw6/memory/MEMORY.md`

No git commit — these are user-local files, not in the repo.

---

### Task 6: Update CLAUDE.md with auto-memory avoidance instruction

**Files:**
- Modify: `~/.claude/CLAUDE.md`

- [ ] **Step 1: Add auto-memory avoidance section**

In `~/.claude/CLAUDE.md`, after the "Memory Hygiene" section (after line 55, before `## Process Discipline`), add:

```markdown

### Auto-Memory Avoidance

Do NOT use Claude Code's built-in auto-memory system (`~/.claude/projects/.../memory/MEMORY.md`)
for storing project knowledge, preferences, or learnings. All persistent memory MUST go through
Hindsight via `retain`. The auto-memory files are reserved for minimal session-level notes only.

If you discover project-relevant information that should persist, use `retain` — never write to
the auto-memory MEMORY.md files.
```

No git commit — `~/.claude/CLAUDE.md` is a user config file, not in the repo.

---

### Task 7: Register PostToolUse hook in current settings (manual)

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: Add PostToolUse hook to settings.json**

Since we're not running `devflow init` right now, manually register the hook. Add a `PostToolUse` entry to the `hooks` object in `~/.claude/settings.json`:

```json
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
```

No git commit — this is a user config file.

---

## Verification

After all tasks are complete, run these end-to-end checks:

1. **PostToolUse hook test:** Run `echo '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title x"}}' | bash lib/hooks/post-pr-continue.sh 2>&1; echo "exit: $?"` — expect continuation message + exit 2
2. **Stop hook with PR:** On a branch with a PR, run `echo '{}' | bash lib/hooks/stop-finish-prompt.sh; echo "exit: $?"` — expect exit 0
3. **Stop hook without PR:** On a branch without a PR, run `echo '{}' | bash lib/hooks/stop-finish-prompt.sh; echo "exit: $?"` — expect exit 2 + error message
4. **Hindsight recall:** `recall("messaging: MR conventions")` returns migrated memory
5. **Settings.json:** Verify PostToolUse entry exists in `~/.claude/settings.json`
