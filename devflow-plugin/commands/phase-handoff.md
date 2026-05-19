---
description: Hand off between phases of the devflow new-feature pipeline. Writes a frozen-state file, marks a chapter, sets terminal title, prompts user to /compact.
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
   - Source-of-truth artefacts (paths exist if their phase ran):
     - Spec: `docs/specs/<feature>.md`
     - Plan: `docs/plans/<feature>-plan.md` or `docs/plans/YYYY-MM-DD-<feature>-plan.md`
     - Test inventory: `docs/specs/<feature>-test-inventory.md`

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
   - Spec: <path or "not yet produced">
   - Plan: <path or "not yet produced">
   - Test inventory: <path or "not yet produced">

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

7. **Prompt the user to clear context.** First, map `<next-phase>` to the actual skill the user should invoke:

   | `<next-phase>` | Skill the user invokes after `/compact` |
   |---|---|
   | `plan` | `/devflow:writing-plans` (or `/superpowers:writing-plans`) |
   | `lock-tests` | `/devflow:lock-tests` |
   | `impl` | `/superpowers:executing-plans` |

   Then output exactly:

   ```
   Phase `<current-phase>` complete. Frozen state at `.devflow/state/${branch_slug}/<current-phase>.md`.

   **Run `/compact` now** to drop the brainstorming context. After it completes, re-invoke me with `<mapped-skill>` — I'll read only from the frozen-state file as source of truth.
   ```

   Substitute `<mapped-skill>` from the table above.

8. **Exit.** Do NOT auto-invoke the next-phase skill. The user's `/compact` is the explicit boundary.

## Important

- This skill writes ONLY to `.devflow/state/${branch_slug}/`. Never edits source code.
- Re-entry: append, never overwrite.
- If `--no-handoff` was passed, do nothing and return.

$ARGUMENTS
