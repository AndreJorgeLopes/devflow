---
description: Hand off between phases of the devflow new-feature pipeline. Writes a frozen-state file, marks a chapter, sets the terminal title, gates on a one-click AskUserQuestion, then emits a copy-pasteable resume prompt for the user to paste after `/clear`.
---

You are at a phase boundary in devflow's new-feature pipeline. Capture the current state to disk, mark the transition, and prompt the user to clear context before the next phase begins.

**Arguments expected (parse `$ARGUMENTS`):**
- `--phase <current-phase>` (required): one of `spec`, `plan`, `lock-tests`
- `--next-phase <next>` (required): one of `plan`, `lock-tests`, `impl`
- `--no-handoff` (optional): skip everything, return immediately (escape hatch)

If `--no-handoff` is present, print "phase-handoff skipped" and exit.

## Steps

1. **Detect context:**
   ```bash
   branch="$(git branch --show-current)"
   worktree_root="$(git rev-parse --show-toplevel)"
   # Sanitize branch name into a filesystem-safe slug.
   # Replaces forward-slashes (from feat/X, fix/X conventions) with hyphens.
   branch_slug="$(echo "$branch" | tr '/' '-')"
   ```
   Extract ticket ID from `$branch` (regex `[A-Z]+-[0-9]+`); if none, use `none`.

2. **Compute target paths:**
   - State dir: `<worktree-root>/.devflow/state/${branch_slug}/`
   - State file: `<state-dir>/<current-phase>.md`
   - Source-of-truth artefacts (paths exist if their phase ran). Scan BOTH locations below and use whichever exists; prefer `docs/superpowers/` if both exist (superpowers default since v5.x):
     - Spec: `docs/superpowers/specs/<feature>.md` OR `docs/specs/<feature>.md`
     - Plan: `docs/superpowers/plans/<feature>.md` OR `docs/plans/<feature>-plan.md` OR `docs/plans/YYYY-MM-DD-<feature>-plan.md`
     - Test inventory: `docs/superpowers/specs/<feature>-test-inventory.md` OR `docs/specs/<feature>-test-inventory.md`

3. **Create the state dir** if it doesn't exist:
   ```bash
   mkdir -p .devflow/state/${branch_slug}
   ```

4. **Write the frozen-state file** at `.devflow/state/${branch_slug}/<current-phase>.md`:

   ```markdown
   # Phase Handoff: <current-phase> → <next-phase>

   **Ticket:** <TICKET-ID or "none">
   **Branch:** <branch-name>
   **Worktree:** <absolute-path>
   **Completed phase:** <current-phase> at <ISO-8601 timestamp>
   **Next phase:** <next-phase>

   ## Source-of-truth artefacts (read these, ignore prior session context)
   - Spec: <worktree-relative path, or "not yet produced">
   - Plan: <worktree-relative path, or "not yet produced">
   - Test inventory: <worktree-relative path, or "not yet produced">

   ## Locked decisions (one-line each)
   - <decision 1>
   - <decision 2>

   ## Open questions for next phase
   - <question 1 or "none">

   ## Todo state at handoff
   <task list snapshot from TaskList tool, or "no tasks tracked">
   ```

   If the file already exists (re-entry into this phase), APPEND a `## Re-entry at <timestamp>` section rather than overwriting.

5. **Mark chapter** (Claude Code). Map `<next-phase>` to a human-readable chapter title:

   | `<next-phase>` | Chapter title |
   |---|---|
   | `plan` | `Plan` |
   | `lock-tests` | `Lock Tests` |
   | `impl` | `Implementation` |

   Call `mark_chapter` with `{title: "<mapped-title> — <TICKET>", summary: "Handed off from <current-phase>"}`.

   If `mark_chapter` is unavailable (e.g. running outside Claude Code), skip silently.

6. **Echo ANSI terminal-title escape:**

   ```bash
   printf '\e]2;%s — %s\007' "<TICKET>" "<mapped-title>"
   ```

7. **Resolve the next-phase invocation text.** Map `<next-phase>` to what the user must paste after `/clear`:

   | `<next-phase>` | Invocation form | Text to paste |
   |---|---|---|
   | `plan` | Slash command (devflow plugin exposes commands) | `/devflow:writing-plans` |
   | `lock-tests` | Slash command (devflow plugin exposes commands) | `/devflow:lock-tests` |
   | `impl` | Natural-language skill trigger (superpowers plugin exposes skills only, NOT slash commands) | `Use the superpowers:executing-plans skill to implement the plan task by task, reading the frozen-state file and artefact paths above.` |

   **Why `impl` is different:** the `superpowers` plugin manifest (`~/.claude/plugins/cache/claude-plugins-official/superpowers/<ver>/.claude-plugin/plugin.json`) declares NO `commands/` directory. Its skills live under `skills/` and Claude invokes them via the `Skill` tool when triggered by matching natural language. `/superpowers:executing-plans` will NOT appear in the user's slash-command picker — paste the natural-language prompt instead.

8. **One-click handoff gate (`AskUserQuestion`).** Ask the user:

   - Question: `Phase \`<current-phase>\` complete. Frozen state written to \`.devflow/state/${branch_slug}/<current-phase>.md\`. Ready to clear context and continue to \`<next-phase>\`?`
   - Header: `Handoff`
   - Single-select. Options:
     - Label: `Show resume prompt (Recommended)` — Description: `Emit copy-pasteable block; you then run /clear and paste it.`
     - Label: `Stay in this session` — Description: `Skip /clear. Risk: stale <current-phase> context biases the next phase.`

   If user picks `Stay in this session`: print `Phase-handoff completed but next-phase skill NOT triggered. Re-invoke phase-handoff later if you change your mind.` and exit.

   If user picks `Show resume prompt`: continue to step 9.

9. **Emit the copy-pasteable resume prompt.** Output the two-step instruction below, with `<placeholders>` substituted, ending in a fenced `text`-tagged code block (use four backticks on the outer fence if the inner block also needs backticks):

   ```
   Phase `<current-phase>` complete. Frozen state at `<worktree-root>/.devflow/state/${branch_slug}/<current-phase>.md`.

   **Step 1:** Run `/clear` now to drop the <current-phase>-phase context entirely. `/clear` is preferred over `/compact` here — `/compact` keeps a biased summary of prior context (often nudging the next phase toward what the summarizer thought mattered); `/clear` gives a true clean slate that reads only the frozen-state file and the artefact paths it lists. The one-time prompt-cache miss is amortized across the next phase.

   **Step 2:** After `/clear`, paste the block below verbatim into the fresh session. It contains every artefact path the next phase needs, so the cold-started session finds its bearings without conversational memory.
   ```

   Then immediately output the resume block as a `text`-tagged fenced code block, ready for the user to triple-click + copy:

   ```text
   Read these source-of-truth artefacts and execute the next phase of <TICKET-ID> (fresh session, no other context):

   - Frozen state (entry point — read first): <worktree-root>/.devflow/state/${branch_slug}/<current-phase>.md
   - Spec: <resolved spec path, or "not yet produced">
   - Plan: <resolved plan path, or "not yet produced">
   - Test inventory: <resolved test-inventory path, or "not yet produced">

   Worktree: <worktree-root>
   Branch: <branch-name>

   Then: <invocation text from step 7's table>
   ```

   Files on disk (spec, plan, test inventory, frozen state, source code) survive `/clear` — only conversation memory is wiped. The resume block hands the new session the exact paths to read; no recall, no guessing.

10. **Exit.** Do NOT auto-invoke the next-phase skill. The user's `/clear` + paste is the explicit boundary.

## Important

- This skill writes ONLY to `.devflow/state/${branch_slug}/`. Never edits source code.
- Re-entry: append, never overwrite.
- If `--no-handoff` was passed, do nothing and return.
- Prefer `/clear` over `/compact` between phases. The frozen-state file plus the four artefact paths it lists are designed to be sufficient for a cold session — no summary needed.
- Invocation form differs by next-phase target: `devflow:*` skills ARE slash commands (`/devflow:writing-plans`, `/devflow:lock-tests`); `superpowers:*` skills are NOT (they invoke via the `Skill` tool from natural language). Step 7's table encodes this; do not hand the user a `/superpowers:*` string.

$ARGUMENTS
