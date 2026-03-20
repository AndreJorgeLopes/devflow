---
description: Post-launch setup for a new feature worktree — detect context, recall memories, and transition to brainstorming.
---

You have been launched inside a feature worktree. Your job is to orient yourself, load context, and start the feature.

**IMPORTANT:** Do NOT create worktrees or branches — that was already handled by `devflow worktree` before this session started.

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

5. **Offer codebase walkthrough (optional).** Ask the user:

   > "Would you like a codebase walkthrough before we start? This traces the full end-to-end flow affected by this task, shows you the actual code at each step, and identifies the key files. Useful if this is an unfamiliar area of the codebase."

   If yes, invoke the `codebase-walkthrough` skill with the feature context. After the walkthrough completes, continue to brainstorming.

6. **Transition to brainstorming.** Once you understand the feature (and optionally completed the walkthrough), invoke the `brainstorming` skill to explore requirements, design, and approach before writing any code.

## Important

- This skill is a **post-launch setup guide** — the worktree already exists.
- Always recall from Hindsight before starting work.
- Never skip the brainstorming step for non-trivial features.
- The codebase walkthrough is optional but recommended for unfamiliar areas.
- If the branch name contains a ticket ID, use it as a namespace prefix in all Hindsight interactions.

$ARGUMENTS
