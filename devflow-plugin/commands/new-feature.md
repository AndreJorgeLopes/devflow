---
description: [0.27.3] Post-launch setup for a new feature worktree — detect context, recall memories, and transition to brainstorming.
---

You have been launched inside a feature worktree. Your job is to orient yourself, load context, and start the feature.

**IMPORTANT:** Do NOT create worktrees or branches — that was already handled by `devflow worktree` before this session started.

> **Eval mode (`$DEVFLOW_EVAL`).** If the env var `DEVFLOW_EVAL` is set you are running under the determinism gate against a throwaway fixture, not a real launch. Produce your normal orientation output to stdout, but perform NO irreversible action: do NOT write `.devflow/` state files, do NOT spawn a session / phase-handoff, do NOT transition into brainstorming. Stop after printing the orientation output.

## Preamble (first action)

1. Detect ticket ID from `git branch --show-current` (regex `[A-Z]+-[0-9]+`); if none, use `none`.
2. Call `mark_chapter` with `{title: "Brainstorm — <TICKET>", summary: "Starting a new feature"}`.
   If `mark_chapter` is unavailable (e.g. running outside Claude Code), skip silently.
3. Set terminal window title (CLI Claude Code only — silent no-op in Claude Desktop):
   ```bash
   [ -t 1 ] && printf '\e]2;%s — Brainstorm\007' "<TICKET>" || true
   ```
   In Claude Desktop there is no controlling terminal — the visible phase signal comes from `mark_chapter` (step 2).

## Steps

1. **Detect workspace context.** Run these commands to understand where you are:

   ```bash
   git branch --show-current
   git log --oneline -1 main 2>/dev/null || git log --oneline -1 master 2>/dev/null
   basename "$(git rev-parse --show-toplevel)"
   ```

   Extract:
   - **Branch name** (e.g., `feat/MES-1234/add-user-metrics`)
   - **Base branch** (`main` or `master`)
   - **Project name** (from the repo root directory)
   - **Ticket ID** if present in the branch name (e.g., `MES-1234`)

   If the current branch is `main` or `master`, this skill does not apply — tell the user to create a worktree first with `devflow worktree <name>`.

2. **Recall relevant memories** using Hindsight. Query with:
   - `"<project>: <domain area from branch name>"`
   - `"<project>: architecture"` (general patterns)
   - If a ticket ID is present: `"<project>: <ticket-id>"`

3. **Present the workspace context:**

   ```
   ## Feature Workspace

   **Branch:** <branch-name>
   **Base:** <base-branch>
   **Project:** <project-name>
   **Ticket:** <ticket-id or "none">

   ### Recalled Context
   - [relevant memories, patterns, and gotchas for this area]
   - [or "No prior memories found for this area"]
   ```

4. **Ask what the feature is about.** If the branch name is descriptive enough, summarize your understanding and ask for confirmation. Otherwise, ask the user to describe the feature.

   **Don't guess from the branch name.** If the branch is descriptive, summarize your reading in one sentence and ask for confirmation. If it leaves gaps (what behavior changes, what success looks like), ask BEFORE recalling more. Silent interpretations compound.

5. **Offer codebase walkthrough (optional).** Ask the user:

   > "Would you like a codebase walkthrough before we start? This traces the full end-to-end flow affected by this task, shows you the actual code at each step, and identifies the key files. Useful if this is an unfamiliar area of the codebase."

   If yes, invoke the `codebase-walkthrough` skill with the feature context. After the walkthrough completes, continue to brainstorming.

   Optionally, you may also offer: "Want a quick architecture diagram of the area being worked on? I can render one via `/devflow:render-diagram` and show it inline." If yes, invoke `/devflow:render-diagram` with the feature/area context (it shows the PNG inline via the Read tool). This is optional and independent of the walkthrough — skip it if the user declines.

6. **Transition to brainstorming.** Once you understand the feature (and optionally completed the walkthrough), invoke `/devflow:brainstorming` (devflow's thin wrapper around the upstream brainstorming skill — always use the devflow surface, never `/brainstorming` or the upstream skill directly) to explore requirements, design, and approach before writing any code.

   The full pipeline from here is:
   ```
   brainstorming → spec-feature → writing-plans → lock-tests → executing-plans → finish-feature
   ```
   The spec → plan → lock-tests → impl boundaries each end with `devflow:phase-handoff` (commits the artefact docs to the branch, gates via one-click `AskUserQuestion`, then spawns a new Claude Desktop session via `mcp__ccd_session__spawn_task` titled `[<TICKET>] [MR#<N>] <Phase>`). The spawned session starts cold in a fresh throwaway worktree; its initial prompt embeds a self-contained `devflow handoff context` block (feature branch/worktree + relative artefact paths + recovery commands) that the next-phase wrapper's Step 0 consumes to re-establish the feature worktree, then reads spec + plan + test inventory as the only authoritative inputs. (Brainstorming → spec-feature is the exception: it stays in the same session, no spawn.)

## Important

- This skill is a **post-launch setup guide** — the worktree already exists.
- Always recall from Hindsight before starting work.
- Never skip the brainstorming step for non-trivial features.
- The codebase walkthrough is optional but recommended for unfamiliar areas.
- If the branch name contains a ticket ID, use it as a namespace prefix in all Hindsight interactions.
- Surface any assumption the branch name or recalled memories lead you to make. The user is one line away — ask before guessing.

$ARGUMENTS
