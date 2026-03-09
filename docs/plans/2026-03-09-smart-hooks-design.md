# Smart Hooks: Stop-Finish-Prompt & Auto-Fetch-Rebase Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add two Claude Code hooks — a Stop hook that prompts users to run the finish-feature flow when implementation is done, and a UserPromptSubmit hook that periodically fetches origin, auto-rebases when safe, and asks when conflicts are detected.

**Architecture:** Two bash scripts in `lib/hooks/` called by Claude Code hooks registered in `~/.claude/settings.json`. The Stop hook uses exit code 2 (block) to re-activate Claude with a finish-feature prompt. The UserPromptSubmit hook runs `git fetch`, compares changed files between branch and main, auto-rebases when no overlap, and presents a 3-option selector when files conflict. Session opt-out uses a `/tmp` flag file keyed by Claude session ID.

**Tech Stack:** Bash scripts, Claude Code hooks JSON protocol (stdin JSON + exit codes), git CLI

**OpenCode Compatibility:** These hooks use the standard Claude Code `settings.json` format. OpenCode issue #12472 plans to read this same file natively — `Stop` maps to `session.idle`, `UserPromptSubmit` maps to a message-submission event. No extra work needed; hooks will activate automatically when OpenCode ships compatibility.

---

## Task 1: Create `lib/hooks/` directory and Stop hook script

**Files:**
- Create: `lib/hooks/stop-finish-prompt.sh`

**Step 1: Create the hook script**

```bash
#!/usr/bin/env bash
# devflow/lib/hooks/stop-finish-prompt.sh
# Claude Code Stop hook — prompts user to run finish-feature flow
# Protocol: reads JSON from stdin, exit 0 = allow stop, exit 2 = block (re-activate)

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

# We're on a feature branch with commits — prompt the user
cat >&2 <<'PROMPT'
You just finished your response on a feature branch with commits ahead of main.

Before ending the session, ask the user:

> **Ready to wrap up?** You have work on this branch that hasn't been merged yet. Would you like to:
>
> 1. **Run the finish-feature flow** — verification, PR creation, session summary, and visualizations (`/devflow:finish-feature`)
> 2. **Continue working** — ask a follow-up question or keep iterating

Wait for the user to choose before proceeding. Do NOT run finish-feature automatically.
PROMPT

exit 2
```

**Step 2: Make the script executable**

Run: `chmod +x lib/hooks/stop-finish-prompt.sh`

**Step 3: Test the script manually with mock stdin**

Run: `echo '{"stop_hook_active": false}' | bash lib/hooks/stop-finish-prompt.sh; echo "Exit: $?"`
Expected: Exit code 2 (if on a feature branch with commits) or 0 (if on main)

Run: `echo '{"stop_hook_active": true}' | bash lib/hooks/stop-finish-prompt.sh; echo "Exit: $?"`
Expected: Exit code 0 (loop prevention)

**Step 4: Commit**

```bash
git add lib/hooks/stop-finish-prompt.sh
git commit -m "feat(hooks): add Stop hook script for finish-feature prompt"
```

---

## Task 2: Create UserPromptSubmit fetch-rebase hook script

**Files:**
- Create: `lib/hooks/prompt-fetch-rebase.sh`

**Step 1: Create the hook script**

```bash
#!/usr/bin/env bash
# devflow/lib/hooks/prompt-fetch-rebase.sh
# Claude Code UserPromptSubmit hook — fetches origin, auto-rebases when safe,
# asks user when conflicts are detected.
# Protocol: reads JSON from stdin, exit 0 = allow, exit 2 = block with message

set -euo pipefail

# Read the hook payload from stdin
payload="$(cat)"

# Extract session ID for the opt-out flag file
session_id="$(echo "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id', 'unknown'))" 2>/dev/null || echo "unknown")"
optout_file="/tmp/devflow-no-rebase-${session_id}"

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
  # Main hasn't moved — nothing to do
  echo "Periodic fetch: branch is up to date with ${main_branch}." >&2
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
    echo "Periodic fetch: rebased on ${main_branch} (${main_ahead} new commits, no conflicts with your changes)." >&2
  else
    # Rebase failed unexpectedly — abort and warn
    git rebase --abort >/dev/null 2>&1 || true
    echo "Periodic fetch: ${main_ahead} new commits on ${main_branch}. Auto-rebase failed — you may want to rebase manually." >&2
  fi
  exit 0
fi

# Overlapping files detected — ask the user
file_count="$(echo "$overlap" | wc -l | tr -d ' ')"
file_list="$(echo "$overlap" | head -10)"

cat >&2 <<PROMPT
**Heads up:** \`${main_branch}\` has ${main_ahead} new commit(s) that touch ${file_count} file(s) you've also changed:

\`\`\`
${file_list}
\`\`\`

$(if [[ "$file_count" -gt 10 ]]; then echo "... and $((file_count - 10)) more files"; fi)

Ask the user how they'd like to handle this:

> 1. **Let me handle it** — I'll rebase and resolve any merge conflicts for you
> 2. **I'll fix it myself** — stop and let the user resolve manually
> 3. **Ignore for this session** — stop fetching and rebasing until the next session

**Important:** If the user picks option 3, run this command to set the opt-out flag:
\`\`\`bash
touch ${optout_file}
\`\`\`
Then acknowledge: "Got it — I won't check for upstream changes for the rest of this session."

Wait for the user to choose before proceeding.
PROMPT

exit 2
```

**Step 2: Make the script executable**

Run: `chmod +x lib/hooks/prompt-fetch-rebase.sh`

**Step 3: Test with mock stdin on a feature branch**

Run: `echo '{"session_id": "test-123"}' | bash lib/hooks/prompt-fetch-rebase.sh; echo "Exit: $?"`
Expected: Exit 0 with "branch is up to date" message (if main hasn't diverged) or exit 2 with conflict prompt

**Step 4: Test opt-out flag**

Run: `touch /tmp/devflow-no-rebase-test-123 && echo '{"session_id": "test-123"}' | bash lib/hooks/prompt-fetch-rebase.sh; echo "Exit: $?"; rm /tmp/devflow-no-rebase-test-123`
Expected: Exit 0 (skipped entirely)

**Step 5: Commit**

```bash
git add lib/hooks/prompt-fetch-rebase.sh
git commit -m "feat(hooks): add UserPromptSubmit hook for smart fetch and rebase"
```

---

## Task 3: Register hooks in `~/.claude/settings.json`

**Files:**
- Modify: `~/.claude/settings.json` (add two new hook entries)
- Modify: `lib/init.sh` (add hook registration to devflow init)

**Step 1: Add hooks to settings.json manually (for immediate use)**

Add to the `"hooks"` object in `~/.claude/settings.json`:

In the `"Stop"` array, add a new entry (alongside existing agent-deck hook):
```json
{
  "hooks": [
    {
      "type": "command",
      "command": "/Users/andrejorgelopes/dev/devflow/lib/hooks/stop-finish-prompt.sh"
    }
  ]
}
```

In the `"UserPromptSubmit"` array, add a new entry (alongside existing agent-deck hook):
```json
{
  "hooks": [
    {
      "type": "command",
      "command": "/Users/andrejorgelopes/dev/devflow/lib/hooks/prompt-fetch-rebase.sh"
    }
  ]
}
```

**Step 2: Verify the JSON is valid**

Run: `python3 -c "import json; json.load(open(os.path.expanduser('~/.claude/settings.json')))" 2>&1 && echo "Valid JSON" || echo "Invalid JSON"`

**Step 3: Commit the hook scripts (settings.json is user-local, not committed)**

```bash
git add lib/hooks/
git commit -m "feat(hooks): register stop-finish-prompt and prompt-fetch-rebase hooks"
```

---

## Task 4: Add hook registration to `devflow init`

**Files:**
- Modify: `lib/init.sh` (add new section between steps 5c and 6)

**Step 1: Add hook registration section to init.sh**

Add a new section `── 5d. Claude Code hooks ──` to `lib/init.sh` that:
1. Checks if `~/.claude/settings.json` exists
2. Uses `python3` + `json` module to read the file
3. Adds the Stop hook entry if not already present (check by command path containing `stop-finish-prompt`)
4. Adds the UserPromptSubmit hook entry if not already present (check by command path containing `prompt-fetch-rebase`)
5. Writes back with `json.dump(indent=2)`
6. Reports what was added/skipped

The hook commands should use `${root}/lib/hooks/<script>` so the path resolves to wherever devflow is cloned.

**Step 2: Test init idempotency**

Run: `devflow init` twice — second run should report "skip" for both hooks.

**Step 3: Commit**

```bash
git add lib/init.sh
git commit -m "feat(init): register devflow hooks in settings.json during init"
```

---

## Task 5: Update the existing plugin Stop hook

**Files:**
- Modify: `devflow-plugin/hooks/hooks.json`

**Step 1: Remove the old echo-based Stop hook**

The old hook was just `echo 'Session ending. Consider running...'`. This is now superseded by `stop-finish-prompt.sh` which handles visualizations and session summary as part of the finish-feature flow prompt.

Update `hooks.json` to remove the Stop hook (the global settings.json hook replaces it):

```json
{
  "hooks": []
}
```

Or if we want to keep plugin-level hooks for future use, leave it empty.

**Step 2: Commit**

```bash
git add devflow-plugin/hooks/hooks.json
git commit -m "refactor(hooks): remove old echo Stop hook, replaced by smart finish-prompt"
```

---

## Task 6: Update the SPIKE task and create a completion record

**Files:**
- Modify: `tasks/P3/SPIKE-hooks-improvement-opportunities.md` (update checklist items that are now addressed)
- Optional: Update `MEMORY.md` with hook architecture notes

**Step 1: Update the SPIKE task checklist**

Mark items 1, 6, and 8 as partially addressed by this implementation:
- Item 1 (Task lifecycle hooks): Stop hook prompts for task completion ✓
- Item 6 (Skill auto-invocation): Stop hook suggests finish-feature ✓
- Item 8 (Task completion automation): Stop hook chains to finish-feature ✓

**Step 2: Retain learnings to Hindsight**

Use `retain()` to save:
- Hook architecture: scripts in `lib/hooks/`, registered in `~/.claude/settings.json`, init sets them up
- Stop hook pattern: exit 2 blocks with stderr prompt, `stop_hook_active` prevents loops
- UserPromptSubmit pattern: session opt-out via `/tmp/devflow-no-rebase-<session_id>`
- OpenCode compat: same hooks will work when OpenCode merges #12472

**Step 3: Commit**

```bash
git add tasks/P3/SPIKE-hooks-improvement-opportunities.md
git commit -m "docs(tasks): update SPIKE-hooks with progress from smart hooks implementation"
```

---

## Task 7: End-to-end validation

**No files to create — manual testing.**

**Step 1: Test Stop hook end-to-end**

1. Open a Claude Code session on a feature branch with commits ahead of main
2. Ask Claude to do something small (e.g., "add a comment to this file")
3. When Claude finishes and tries to stop, verify the finish-feature prompt appears
4. Choose "Continue working" — verify Claude continues
5. Let it stop again — verify the prompt appears again
6. Choose "Run finish-feature flow" — verify it launches the skill

**Step 2: Test UserPromptSubmit hook end-to-end**

1. Create a feature branch, make a commit
2. On another branch or directly on main, push a commit that does NOT touch the same files
3. Switch back to the feature branch, start a Claude session
4. Submit any prompt — verify "rebased on main, no conflicts" message
5. Now push a commit to main that DOES touch a file you changed on the feature branch
6. Submit another prompt — verify the 3-option conflict selector appears
7. Choose option 3 (ignore for session) — verify subsequent prompts skip the check

**Step 3: Test loop prevention**

1. On a feature branch, trigger the Stop hook
2. Choose "Continue working"
3. Let Claude finish again — verify it doesn't enter an infinite loop (second Stop should show the prompt once more, not loop)

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat(hooks): smart Stop + UserPromptSubmit hooks for finish-feature and auto-rebase

- Stop hook prompts to run finish-feature flow when implementation is done
- UserPromptSubmit hook fetches origin, auto-rebases when safe, asks on conflicts
- Session opt-out via /tmp flag file for conflict-prone sessions
- devflow init registers hooks in ~/.claude/settings.json
- OpenCode compatible via standard hooks protocol (issue #12472)"
```
