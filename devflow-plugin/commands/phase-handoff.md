---
description: [0.4.0] Hand off between phases of the devflow new-feature pipeline. Writes a frozen-state file, marks a chapter, sets the terminal title, gates on a one-click AskUserQuestion, then spawns a new session for the next phase via `mcp__ccd_session__spawn_task` so it shows up in the Claude Desktop sidebar with a deterministic title.
---

You are at a phase boundary in devflow's new-feature pipeline. Capture the current state to disk, mark the transition in the CURRENT session, then spawn a NEW session (`mcp__ccd_session__spawn_task`) for the next phase. The new session starts cold — its only context is the prompt you hand it, which points at the frozen-state file plus absolute artefact paths.

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
   Extract ticket ID from `$branch` (regex `[A-Z]+-[0-9]+`); if none, use `TICKET-000` as a deterministic placeholder so titles remain consistent.

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

   **Ticket:** <TICKET-ID or "TICKET-000">
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

5. **Mark chapter in the CURRENT session** (Claude Code). Map `<current-phase>` to a human-readable chapter title to mark the phase you are LEAVING:

   | `<current-phase>` | Chapter title for the current session |
   |---|---|
   | `spec` | `Spec complete` |
   | `plan` | `Plan complete` |
   | `lock-tests` | `Lock Tests complete` |

   Call `mark_chapter` with `{title: "<mapped-title> — <TICKET>", summary: "Handing off to <next-phase> phase"}`.

   If `mark_chapter` is unavailable (e.g. running outside Claude Code), skip silently.

6. **Set terminal window title for the CURRENT session (CLI Claude Code only — silent no-op in Claude Desktop):**

   ```bash
   [ -t 1 ] && printf '\e]2;%s — %s\007' "<TICKET>" "<current-phase mapped title>" || true
   ```

   In Claude Desktop there is no controlling terminal (stdout is captured by the harness, `/dev/tty` is unavailable), so the escape would never reach a window manager. The visible phase signal in Claude Desktop comes from `mark_chapter` + the spawned-session sidebar entry (step 9).

7. **Resolve next-phase metadata.** Map `<next-phase>` to its display label and invocation form:

   | `<next-phase>` | Display label (for spawn_task title) | Skill invocation in the new session |
   |---|---|---|
   | `plan` | `Plan` | `/devflow:writing-plans` |
   | `lock-tests` | `Lock Tests` | `/devflow:lock-tests` |
   | `impl` | `Implementation` | `/devflow:executing-plans` |

   **Why every entry uses a `/devflow:` wrapper:** devflow's policy is that no skill in the pipeline ever invokes an upstream skill directly — all calls go through a devflow wrapper. `/devflow:executing-plans` is the wrapper for the upstream executing-plans skill; it delegates the per-task red-green-refactor loop to the upstream flow AND intercepts the terminal handoff so it goes to `/devflow:finish-feature` instead of the upstream default. If the wrapper is missing on a given install, the user can fall back to invoking the upstream skill directly — but the wrapper is the canonical entry point.

8. **Detect MR/PR number for the current branch.** Optional — included in the spawned-session title when available:

   ```bash
   # Pick CLI by git remote — prefer gh if remote is github.com, glab if gitlab. Try both as fallback.
   if git remote -v | grep -q "github.com"; then
     mr_num="$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null)"
     [ -z "$mr_num" ] && mr_num="$(glab mr list --source-branch "$branch" --output json 2>/dev/null | jq -r '.[0].iid // empty' 2>/dev/null)"
   else
     mr_num="$(glab mr list --source-branch "$branch" --output json 2>/dev/null | jq -r '.[0].iid // empty' 2>/dev/null)"
     [ -z "$mr_num" ] && mr_num="$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null)"
   fi
   ```

   If neither CLI returns a number, `mr_num` stays empty — the title just omits the `[MR#N]` slot.

9. **Build the spawn_task parameters.** Required fields:

   - `title`: deterministic format `[<TICKET>] [MR#<N>] <next-phase-label>`. Examples:
     - With MR: `[MES-4282] [MR#29] Implementation`
     - Without MR: `[MES-4282] Lock Tests`
     - Ticketless flow: `[TICKET-000] Plan` (where the suffix is one of the next-phase labels in the table — `Plan`, `Lock Tests`, or `Implementation`. The pipeline's first phase `Brainstorm` is the ENTRY point, not a `<next-phase>` value that phase-handoff is ever called with — phase-handoff is invoked from `spec-feature`, `writing-plans`, or `lock-tests`, never from `new-feature`.)

     If `<mr_num>` is empty, OMIT the `[MR#…]` slot entirely (do NOT emit `[MR#]` with no number). Title must be ≤60 chars — the format above stays well within the budget for typical ticket/MR sizes.

   - `tldr`: 1-2 sentence tooltip. Format: `Continue <feature-area-from-branch>: <next-phase-label> phase. Reads <frozen-state-relpath> + <N> artefact path(s).` Keep under 200 chars.

   - `prompt`: self-contained initial message for the new session. The new session has ZERO conversational memory; the prompt must include everything it needs.

     **CRITICAL ordering: the FIRST LINE of the prompt MUST be the slash-command invocation for the next phase.** Claude Code's plugin runtime triggers a slash command only when it is the leading content of the user message. If the slash command is buried mid-body, the spawned session treats the prompt as a conversational request — reads the files, then waits for further input — instead of auto-invoking the next-phase skill. Lead with the slash, then provide the context as supporting paths the wrapper skill reads next. Format:

     ```
     <invocation slash command from step 7's table>

     You are continuing devflow's new-feature pipeline for <TICKET-ID> at the <next-phase-label> phase. The slash command above is your first action — invoke it now, then read these absolute paths inside the invoked skill:

     - Frozen state (entry point — read first): <worktree-root>/.devflow/state/${branch_slug}/<current-phase>.md
     - Spec: <worktree-root>/<rel-spec-path>  (or "not yet produced")
     - Plan: <worktree-root>/<rel-plan-path>  (or "not yet produced")
     - Test inventory: <worktree-root>/<rel-test-inventory-path>  (or "not yet produced")

     Worktree: <worktree-root>
     Branch: <branch-name>
     Ticket: <TICKET-ID>
     <If mr_num: MR/PR: #<mr_num>>

     Do NOT carry over assumptions from any prior session — the frozen-state file and artefact paths above are the only authoritative inputs.
     ```

     **Example for an `impl` phase handoff on ticket MES-4282, MR #29:**

     ```
     /devflow:executing-plans

     You are continuing devflow's new-feature pipeline for MES-4282 at the Implementation phase. The slash command above is your first action — invoke it now, then read these absolute paths inside the invoked skill:

     - Frozen state (entry point — read first): /Users/foo/dev/.worktrees/messaging/MES-4282/.devflow/state/MES-4282/lock-tests.md
     - Spec: /Users/foo/dev/.worktrees/messaging/MES-4282/docs/specs/whatsapp-user-send.md
     - Plan: /Users/foo/dev/.worktrees/messaging/MES-4282/docs/plans/2026-05-27-whatsapp-user-send-plan.md
     - Test inventory: /Users/foo/dev/.worktrees/messaging/MES-4282/docs/specs/whatsapp-user-send-test-inventory.md

     Worktree: /Users/foo/dev/.worktrees/messaging/MES-4282
     Branch: feat/MES-4282/whatsapp-user-send
     Ticket: MES-4282
     MR/PR: #29

     Do NOT carry over assumptions from any prior session — the frozen-state file and artefact paths above are the only authoritative inputs.
     ```

10. **One-click handoff gate (`AskUserQuestion`).** Ask the user:

    - Question: `Phase \`<current-phase>\` complete. Spawn a new session for the \`<next-phase>\` phase? Title will be: \`<computed-title>\``
    - Header: `Handoff`
    - Single-select. Options:
      - Label: `Spawn new session (Recommended)` — Description: `Creates a fresh session in your Claude Desktop sidebar with the title above. Manually drag it into the same group as this session if needed.`
      - Label: `Stay in this session` — Description: `Skip the spawn. Risk: stale <current-phase> context biases the next phase. Re-invoke phase-handoff later if you change your mind.`

    If user picks `Stay in this session`: print `Phase-handoff completed but new-session NOT spawned. Re-invoke phase-handoff later to spawn when ready.` and exit.

    If user picks `Spawn new session`: continue to step 11.

11. **Spawn the new session via `mcp__ccd_session__spawn_task`.** Call the tool with the three parameters built in step 9 (`title`, `tldr`, `prompt`).

    After the call returns successfully, output exactly:

    ```
    Spawned new session: `<computed-title>` — visible in the Claude Desktop sidebar.

    The new session starts cold and reads only the frozen-state file + absolute artefact paths above. To continue work, switch to that session in the sidebar.

    Note: `spawn_task` cannot place the new session in a specific group (Claude Desktop UI-only metadata, not exposed via MCP). If you organize by group, drag the new session into the same group as this one.
    ```

    Then exit.

## Important

- This skill writes ONLY to `.devflow/state/${branch_slug}/`. Never edits source code.
- Re-entry: append, never overwrite.
- If `--no-handoff` was passed, do nothing and return.
- The CURRENT session stays open after the handoff — `spawn_task` does NOT close it. The user can keep it as an archive/reference and switch to the new session for the next phase.
- `spawn_task` is a one-shot spawn — it does NOT auto-resume the new session or auto-invoke the next skill. The new session waits in the sidebar for the user to open it; on first open, the agent there sees the `prompt` and acts on it.
- Group placement is NOT supported by `spawn_task` (no `group`/`groupId` parameter on the MCP tool, and groups are Claude Desktop UI-only metadata). Manual drag-into-group required after spawn.
- Invocation form per next-phase: ALL three next-phases use a `/devflow:<name>` slash command (`/devflow:writing-plans`, `/devflow:lock-tests`, `/devflow:executing-plans`). The `executing-plans` slot points at devflow's wrapper, which internally delegates to upstream `superpowers:executing-plans` and forces the post-implementation handoff to `/devflow:finish-feature`. Never hand the spawned session a `/superpowers:*` slash or a natural-language skill trigger — the devflow wrapper is the canonical entry point for every phase.

$ARGUMENTS
