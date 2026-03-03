---
description: Finish a feature — run checks, generate a commit message, merge via Worktrunk, and retain session learnings.
---

You are finishing a feature. This command runs the full completion pipeline.

## Steps

1. **Assess the current state**. Run:

   ```bash
   git status
   git diff --stat
   git log --oneline main..HEAD
   ```

   Confirm we're in a feature worktree and there are changes to finalize.

2. **Run the pre-push checks**. Execute the full check pipeline:

   ```bash
   cn check
   ```

   If `cn` is not available, run lint and type checks directly:

   ```bash
   yarn lint
   yarn build
   ```

   Also run relevant tests:

   ```bash
   yarn test --changedSince=main
   ```

3. **If checks fail**, report the failures and ask the user to fix them before proceeding. Do NOT continue past this step with failing checks.

4. **Stage and commit**. If there are uncommitted changes:
   - Stage all relevant changes: `git add -A`
   - Generate a commit message by analyzing the full diff. The message should:
     - Follow conventional commits format (feat:, fix:, refactor:, etc.)
     - Be concise (1-2 lines)
     - Reference the ticket ID if present in the branch name
   - Present the commit message to the user for approval before committing.

5. **Merge via Worktrunk**. Run:

   ```bash
   worktrunk merge
   ```

   If `worktrunk` is not available, fall back to manual merge:

   ```bash
   git checkout main
   git merge --no-ff <feature-branch>
   ```

6. **Reflect and retain learnings**. Review the session:
   - What was built?
   - Were there any notable decisions, gotchas, or patterns discovered?
   - Use the `hindsight_retain` MCP tool to store each learning.

7. **Clean up the worktree**:

   ```bash
   worktrunk clean
   ```

8. **Present the summary**:

   ```
   ## Feature Complete

   **Feature:** <name>
   **Commits:** <count>
   **Files changed:** <count>

   ### Checks
   - [PASS/FAIL] Lint
   - [PASS/FAIL] Types
   - [PASS/FAIL] Tests

   ### Learnings Retained
   - [list of retained memories]

   ### Next Steps
   - Push to remote: `git push`
   - Create PR: use `/create-pr`
   ```

$ARGUMENTS
