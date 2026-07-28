---
description: [0.22.0] Hand off between phases of the devflow new-feature pipeline. Writes a frozen-state file, marks a chapter, sets the terminal title, gates on a one-click AskUserQuestion, then spawns a new session for the next phase via `mcp__ccd_session__spawn_task` so it shows up in the Claude Desktop sidebar with a deterministic title.
---

You are at a phase boundary in devflow's new-feature pipeline. Capture the current state to disk, **commit the phase artefacts to the feature branch so they survive worktree removal**, mark the transition in the CURRENT session, then spawn a NEW session (`mcp__ccd_session__spawn_task`) for the next phase.

**Critical fact about `spawn_task` — the spawned session does NOT land on this branch.** `spawn_task` ALWAYS forks a *fresh throwaway worktree off the default branch*; there is no parameter to pin it to an existing worktree or branch. So the new session starts cold, in the wrong worktree, on the wrong branch. Two consequences drive this skill's design:

1. **The prompt must be fully self-contained AND tell the new session to re-establish the feature worktree as its very first action.** Every wrapper it can land in (`writing-plans`, `lock-tests`, `executing-plans`) has a matching **Step 0 — Re-establish the feature worktree** that consumes the machine-readable `devflow handoff context` block this prompt provides.
2. **Artefacts must be durable.** Because the artefacts live only in a worktree that may be removed between phases, this skill commits the spec/plan/test-inventory docs to the feature branch (step 4b). Git worktrees share one object database, so a committed artefact survives `git worktree remove` — the branch ref and its commits persist in the main clone's `.git` with no push required, and the spawned session can recreate the worktree or read any artefact via `git show <branch>:<path>`. (The `.devflow/state/<slug>/<phase>.md` frozen-state file is written for the CURRENT session's local record and re-entry, but is NOT committed — force-adding it would leak per-branch scaffolding into the merged default branch, and the locked decisions it holds are already carried, durably, inside the self-contained spawn prompt.)

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
   # Main clone root (shared object DB). git-common-dir points at the ONE real .git even from a
   # linked worktree; its parent is where `git worktree add` recreates this worktree, and where
   # `git show <branch>:<path>` can read any committed artefact if the worktree is gone.
   main_repo="$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd)"
   # Sanitize branch name into a filesystem-safe slug.
   # Replaces forward-slashes (from feat/X, fix/X conventions) with hyphens.
   branch_slug="$(echo "$branch" | tr '/' '-')"
   ```
   Extract ticket ID from `$branch` (regex `[A-Z]+-[0-9]+`); if none, use `TICKET-000` as a deterministic placeholder so titles remain consistent.

   > **You must be in the feature worktree when this skill runs.** phase-handoff is invoked at the tail of `spec-feature` / `writing-plans` / `lock-tests`, each of which runs its **Step 0 — Re-establish the feature worktree** first, so `git` here resolves to the correct branch. If `$branch` is the default branch (`main`/`master`) or otherwise not the feature branch you expect, STOP — committing and handing off from the wrong branch is the exact failure this design prevents.

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

4b. **Commit the artefact docs to the feature branch (durability).** This is what lets the spawned session recover after a worktree removal — worktrees share the object DB, so the branch keeps these commits even if this worktree is later deleted. Commit ONLY the spec/plan/test-inventory docs (they belong in the branch / MR anyway); do NOT commit the `.devflow/state` frozen-state file (force-adding it leaks per-branch scaffolding onto the merged default branch — the decisions are carried in the spawn prompt instead). Local commit only; no push.

   ```bash
   # Stage only the source-of-truth docs that exist. NEVER `git add -A`/`git add .` — that would
   # sweep in the user's unrelated working-tree changes.
   for a in "<rel-spec-path>" "<rel-plan-path>" "<rel-test-inventory-path>"; do
     [ -n "$a" ] && [ -f "$a" ] && git add "$a"
   done

   if git diff --cached --quiet; then
     # Genuine no-op (re-entry, or the docs were already committed) — not a failure.
     echo "phase-handoff: no new artefact changes to commit — continuing"
   else
     # --no-verify + HUSKY=0: this is internal pipeline bookkeeping (docs only), NOT a code change.
     # The target repo's husky/lint-staged pre-commit hooks (messaging, hydra, etc.) must not block
     # it — and, critically, must not fail it silently. A masked failure here would leave the branch
     # without the artefacts and defeat the whole recovery design.
     HUSKY=0 git commit --no-verify -m "docs(devflow): persist <current-phase> artefacts for <next-phase> handoff [skip ci]" \
       || echo "phase-handoff: WARNING — artefact commit FAILED. Durability is NOT guaranteed; do not rely on branch/\`git show\` recovery until this is resolved."
   fi
   ```

   Distinguish a genuine no-op (`git diff --cached --quiet` = nothing staged) from a real commit failure: the no-op path prints an informational line and continues; a real failure prints a loud WARNING (it must never be reported as success). Never `git push` from here — pushing triggers CI on a shared branch and is not needed for same-machine worktree-drop survival. If cross-machine continuity is ever required, that is a manual `git push` the user runs, not this skill.

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

     **CRITICAL ordering: the FIRST LINE of the prompt MUST be the slash-command invocation for the next phase.** Claude Code's plugin runtime triggers a slash command only when it is the leading content of the user message. If the slash command is buried mid-body, the spawned session treats the prompt as a conversational request — reads the files, then waits for further input — instead of auto-invoking the next-phase skill. Lead with the slash; the rest of the prompt is the self-contained `devflow handoff context` block the wrapper's **Step 0** consumes to re-establish the feature worktree before reading anything.

     **The prompt must be self-contained.** The spawned session starts in the WRONG worktree on the WRONG branch (see the intro). It must be able to (a) recover the feature worktree from the block alone, and (b) proceed even if that worktree was removed — hence the `Main repo` line and the `git worktree add` / `git show` fallbacks. Embed the locked decisions and open questions inline (do not merely point at the frozen-state file — that file might be the thing that got removed; it is committed as a backup, but the prompt is the primary carrier). Artefact paths are RELATIVE to the feature worktree, because Step 0 `cd`s into it. Format:

     ```
     <invocation slash command from step 7's table>

     You are continuing devflow's new-feature pipeline for <TICKET-ID> at the <next-phase-label> phase.

     WARNING: you have been spawned into a fresh throwaway worktree that is NOT on the feature branch. The invoked skill's "Step 0 — Re-establish the feature worktree" will move you to the real one using the block below, then read the artefacts. Do all work in the feature worktree.

     --- devflow handoff context (authoritative; ignore any prior-session assumptions) ---
     Ticket: <TICKET-ID>
     Feature branch: <branch-name>
     Feature worktree: <worktree-root>
     Main repo (shared .git): <main-repo-root>
     <If mr_num: MR/PR: #<mr_num>>

     Artefacts committed on `<branch-name>` (paths relative to the feature worktree; open with the Read/Edit tool as <worktree-root>/<rel-path>, which needs an absolute path):
     - Spec: <rel-spec-path>  (or "not yet produced")
     - Plan: <rel-plan-path>  (or "not yet produced")
     - Test inventory: <rel-test-inventory-path>  (or "not yet produced")
     Frozen-state file (worktree-local, NOT committed — may be absent after a worktree drop; THIS block is the authoritative fallback):
     - .devflow/state/<branch_slug>/<current-phase>.md

     Recovery — if the feature worktree is missing, recreate it (branch + commits live in the shared .git):
       git -C "<main-repo-root>" worktree add "<worktree-root>" "<branch-name>"
     Any committed artefact is readable even with no worktree via:
       git -C "<main-repo-root>" show "<branch-name>:<rel-path>"

     Locked decisions:
     - <decision 1>
     - <decision 2>

     Open questions for this phase:
     - <question 1 or "none">
     --- end devflow handoff context ---

     The slash command on line 1 is your first action — invoke it now. Its Step 0 re-establishes the feature worktree from the block above; the artefacts are then the only authoritative inputs.
     ```

     **Example for an `impl` phase handoff on ticket MES-4282, MR #29:**

     ```
     /devflow:executing-plans

     You are continuing devflow's new-feature pipeline for MES-4282 at the Implementation phase.

     WARNING: you have been spawned into a fresh throwaway worktree that is NOT on the feature branch. The invoked skill's "Step 0 — Re-establish the feature worktree" will move you to the real one using the block below, then read the artefacts. Do all work in the feature worktree.

     --- devflow handoff context (authoritative; ignore any prior-session assumptions) ---
     Ticket: MES-4282
     Feature branch: feat/MES-4282/whatsapp-user-send
     Feature worktree: /Users/foo/dev/.worktrees/messaging/feat-MES-4282-whatsapp-user-send
     Main repo (shared .git): /Users/foo/dev/aircall/messaging
     MR/PR: #29

     Artefacts committed on `feat/MES-4282/whatsapp-user-send` (paths relative to the feature worktree; open with the Read/Edit tool as <worktree-root>/<rel-path>, which needs an absolute path):
     - Spec: docs/specs/whatsapp-user-send.md
     - Plan: docs/plans/2026-05-27-whatsapp-user-send-plan.md
     - Test inventory: docs/specs/whatsapp-user-send-test-inventory.md
     Frozen-state file (worktree-local, NOT committed — may be absent after a worktree drop; THIS block is the authoritative fallback):
     - .devflow/state/feat-MES-4282-whatsapp-user-send/lock-tests.md

     Recovery — if the feature worktree is missing, recreate it (branch + commits live in the shared .git):
       git -C "/Users/foo/dev/aircall/messaging" worktree add "/Users/foo/dev/.worktrees/messaging/feat-MES-4282-whatsapp-user-send" "feat/MES-4282/whatsapp-user-send"
     Any committed artefact is readable even with no worktree via:
       git -C "/Users/foo/dev/aircall/messaging" show "feat/MES-4282/whatsapp-user-send:docs/specs/whatsapp-user-send.md"

     Locked decisions:
     - Learned-format cache keyed by numberUUID in MessagingCacheTable; write-on-change only.
     - No SAM/IAM change; reuse existing dynamo-cache primitives.

     Open questions for this phase:
     - none

     --- end devflow handoff context ---

     The slash command on line 1 is your first action — invoke it now. Its Step 0 re-establishes the feature worktree from the block above; the artefacts are then the only authoritative inputs.
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

    The new session starts cold in a fresh throwaway worktree; its Step 0 re-establishes the feature worktree/branch from the self-contained handoff context, then reads the artefacts (committed on the branch). To continue work, switch to that session in the sidebar.

    Note: `spawn_task` cannot place the new session in a specific group (Claude Desktop UI-only metadata, not exposed via MCP). If you organize by group, drag the new session into the same group as this one.

    Note: the spawn creates a fresh throwaway worktree that the new session abandons in favor of the feature worktree — it becomes an orphan. Prune orphans periodically (see Important, below).
    ```

    Then exit.

## Important

- This skill writes the frozen-state file under `.devflow/state/${branch_slug}/` (local record + re-entry only — NOT committed) and `git add`+commits ONLY the existing spec/plan/test-inventory docs (step 4b, `--no-verify`, docs-only, never `git add -A`). It never edits source code and never pushes.
- Must run in the feature worktree, on the feature branch (the invoking wrapper's Step 0 guarantees this). If `git branch --show-current` returns the default branch, STOP — do not commit or hand off from the wrong branch.
- Re-entry: append to the frozen-state file, never overwrite; the step-4b commit is a guarded no-op when nothing changed.
- If `--no-handoff` was passed, do nothing and return.
- The CURRENT session stays open after the handoff — `spawn_task` does NOT close it. The user can keep it as an archive/reference and switch to the new session for the next phase.
- `spawn_task` is a one-shot spawn — it does NOT auto-resume the new session or auto-invoke the next skill. The new session waits in the sidebar for the user to open it; on first open, the agent there sees the `prompt` and acts on it.
- **Orphan worktrees are an unavoidable side effect.** `spawn_task` forks a fresh throwaway worktree off the default branch on every handoff; the spawned session abandons it (Step 0 moves to the feature worktree), leaving an orphan under the worktrees dir with a random `adjective-surname-hex` name whose same-named branch just points at a default-branch commit. devflow does NOT auto-prune them — removing a live session's cwd is unsafe. Prune periodically once the phase session has moved on:
  ```bash
  # From the main clone; skip real feature branches and any worktree with uncommitted work.
  git -C "<main-repo>" worktree list
  git -C "<main-repo>" worktree remove "<orphan-worktree-path>"   # refuses if dirty; --force to override
  git -C "<main-repo>" branch -D "<orphan-branch-name>"          # only if `git log <default>..<branch>` is empty
  ```
- Group placement is NOT supported by `spawn_task` (no `group`/`groupId` parameter on the MCP tool, and groups are Claude Desktop UI-only metadata). Manual drag-into-group required after spawn.
- Invocation form per next-phase: ALL three next-phases use a `/devflow:<name>` slash command (`/devflow:writing-plans`, `/devflow:lock-tests`, `/devflow:executing-plans`). The `executing-plans` slot points at devflow's wrapper, which internally delegates to upstream `superpowers:executing-plans` and forces the post-implementation handoff to `/devflow:finish-feature`. Never hand the spawned session a `/superpowers:*` slash or a natural-language skill trigger — the devflow wrapper is the canonical entry point for every phase.

$ARGUMENTS
