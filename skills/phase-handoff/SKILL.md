---
name: phase-handoff
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

6. **Set terminal window title (CLI Claude Code only — silent no-op in Claude Desktop):**

   ```bash
   [ -t 1 ] && printf '\e]2;%s — %s\007' "<TICKET>" "<mapped-title>" || true
   ```

   In Claude Desktop there is no controlling terminal (stdout is captured by the harness, `/dev/tty` is unavailable), so the escape would never reach a window manager. The visible phase signal comes from `mark_chapter` (step 5).

7. **Resolve the next-phase invocation text.** Map `<next-phase>` to what the user must paste after `/clear`:

   | `<next-phase>` | Text to paste |
   |---|---|
   | `plan` | `/devflow:writing-plans` |
   | `lock-tests` | `/devflow:lock-tests` |
   | `impl` | `/executing-plans` |

   **Note on `impl`:** the `superpowers` plugin packages `executing-plans` as a skill (under its `skills/` tree), not as a manifest-declared command. Claude Code's plugin runtime auto-exposes skill names as slash commands, so `/executing-plans` resolves to the superpowers skill at invocation time. If the slash command picker does not surface it in a given install (older Claude Code, plugin disabled, etc.), invoke it as a natural-language Skill trigger instead: `Use the superpowers:executing-plans skill to implement the plan task by task, reading the frozen-state file and artefact paths above.`

8. **One-click handoff gate (`AskUserQuestion`).** Ask the user:

   - Question: `Phase \`<current-phase>\` complete. Frozen state written to \`.devflow/state/${branch_slug}/<current-phase>.md\`. Ready to clear context and continue to \`<next-phase>\`?`
   - Header: `Handoff`
   - Single-select. Options:
     - Label: `Show resume prompt (Recommended)` — Description: `Emit copy-pasteable block; you then run /clear and paste it.`
     - Label: `Stay in this session` — Description: `Skip /clear. Risk: stale <current-phase> context biases the next phase.`

   If user picks `Stay in this session`: print `Phase-handoff completed but next-phase skill NOT triggered. Re-invoke phase-handoff later if you change your mind.` and exit.

   If user picks `Show resume prompt`: continue to step 9.

9. **Emit the copy-pasteable resume prompt.** First print the two preparatory sentences below as PROSE (no code fence — they need to render as bold-formatted markdown for the user, not as literal code). Then emit ONE fenced `text`-tagged code block containing the resume content the user will triple-click + copy.

   Preparatory prose (substitute `<placeholders>` before emitting):

   Phase `<current-phase>` complete. Frozen state at `<worktree-root>/.devflow/state/${branch_slug}/<current-phase>.md`.

   **Step 1:** Run `/clear` now to drop the `<current-phase>`-phase context entirely. `/clear` is preferred over `/compact` here — `/compact` keeps a biased summary of prior context (often nudging the next phase toward what the summarizer thought mattered); `/clear` gives a true clean slate that reads only the frozen-state file and the artefact paths it lists. The one-time prompt-cache miss is amortized across the next phase.

   **Step 2:** After `/clear`, paste the block below verbatim into the fresh session. It contains every artefact path the next phase needs, so the cold-started session finds its bearings without conversational memory.

   Then output the resume block — a SINGLE `text`-tagged fenced code block. All artefact paths inside the block MUST be ABSOLUTE paths (resolved from `$worktree_root`), so the cold-started session reads them correctly regardless of cwd:

   ```text
   Read these source-of-truth artefacts and execute the next phase of <TICKET-ID> (fresh session, no other context). All paths below are absolute — readable from any cwd:

   - Frozen state (entry point — read first): <worktree-root>/.devflow/state/${branch_slug}/<current-phase>.md
   - Spec: <worktree-root>/<rel-spec-path>  (or "not yet produced")
   - Plan: <worktree-root>/<rel-plan-path>  (or "not yet produced")
   - Test inventory: <worktree-root>/<rel-test-inventory-path>  (or "not yet produced")

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
