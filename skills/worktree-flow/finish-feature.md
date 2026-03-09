---
description: Finish a feature — run verification, create PR, retain learnings, and hand off cleanup to the terminal.
---

You are finishing a feature. Run the full completion pipeline before handing off to the developer for worktree cleanup.

**IMPORTANT:** Do NOT clean up the worktree or switch branches from inside this session — that is a terminal action performed by the developer after the session ends.

## Steps

1. **Assess the current state.** Run:

   ```bash
   git branch --show-current
   git status
   git diff --stat
   git log --oneline main..HEAD 2>/dev/null || git log --oneline master..HEAD
   ```

   Confirm you are on a feature branch (not `main`/`master`) and there are changes to finalize.

2. **Run verification checks.** Execute the full check pipeline:

    ```bash
    devflow check
    ```

    If `devflow check` is not available, run lint, types, and tests directly:

   ```bash
   yarn lint
   yarn build
   yarn test --changedSince=main
   ```

   **If checks fail**, report the failures clearly and stop. Do NOT continue past this step with failing checks. Help the user fix issues if they ask.

3. **Stage and commit.** If there are uncommitted changes:
   - Stage relevant changes: `git add -A`
   - Analyze the full diff to generate a commit message:
     - Follow conventional commits format (`feat:`, `fix:`, `refactor:`, etc.)
     - Be concise (1-2 lines)
     - Reference the ticket ID if present in the branch name
   - Present the commit message to the user for approval before committing.

4. **Push and create PR.** Push the branch and create a pull request:

   ```bash
   git push -u origin HEAD
   ```

   Then create the PR using `gh`:

   ```bash
   gh pr create --title "<title>" --body "<body>"
   ```

   The PR body should include:
   - Summary of changes (2-3 bullet points)
   - Ticket reference if applicable
   - Testing notes (what was verified)

   Present the PR URL to the user.

5. **Retain session learnings.** Review the session and retain important discoveries:
   - Architecture decisions made during this feature
   - Gotchas or non-obvious patterns encountered
   - Bug root causes and fixes
   - Use Hindsight `retain` for each learning, tagged with the project name

6. **Present the summary and hand off cleanup:**

   ```
   ## Feature Complete

   **Branch:** <branch-name>
   **PR:** <pr-url>
   **Commits:** <count>
   **Files changed:** <count>

   ### Checks
   - [PASS/FAIL] Lint
   - [PASS/FAIL] Types
   - [PASS/FAIL] Tests

   ### Learnings Retained
   - [list of retained memories]

   ### Cleanup (run from your terminal)
   To remove the worktree after PR is merged:
     agent-deck worktree finish "<session>"
     # or manually:
     wt drop <branch-name>
   ```

## Important

- Never merge to `main` from inside the agent — use PRs.
- Never clean up the worktree from inside the agent — that's a terminal action.
- If checks fail, stop and help fix. Do not skip verification.
- Always retain learnings before ending the session.

$ARGUMENTS
