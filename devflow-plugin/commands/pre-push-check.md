---
description: [devflow v0.1.0] Run the full pre-push review pipeline — code review checks, self-review against CLAUDE.md, and a final report.
---

You are about to push code. Run the full pre-push quality pipeline before pushing.

## Steps

1. **Check what's being pushed**. Run `git diff --stat` and `git log --oneline origin/HEAD..HEAD` to understand the scope of changes.

2. **Run code review checks**. Execute:

   ```bash
   devflow check
   ```

   Capture and parse the output. This uses Claude Code (primary) or OpenCode (fallback) to review against `.devflow/checks/*.md` rules. If neither CLI is available, fall back to running the project's lint and type-check commands directly (e.g., `yarn lint`, `yarn build`).

3. **Self-review the diff against CLAUDE.md**. Read the project's `CLAUDE.md` file and review the staged changes against its rules:
   - Are naming conventions followed?
   - Are the architectural patterns respected (clean architecture layers)?
   - Are imports using the correct path aliases?
   - Is error handling done properly (no raw console.log, proper error classes)?
   - Are there any hardcoded secrets or credentials?
   - Is input validation present where needed?
   - Are tests included for new functionality?

4. **Check for common issues**:
   - Files that shouldn't be committed (.env, credentials, node_modules)
   - `console.log` statements left in production code
   - `any` type usage in TypeScript
   - Missing error handling in async functions
   - TODOs without ticket references

5. **Generate the report**:

   ```
   ## Pre-Push Check Report

   **Branch:** [branch name]
   **Commits:** [number] commits ahead of origin

    ### Code Review Results
   - [PASS/FAIL] [details]

   ### CLAUDE.md Compliance
   - [PASS/WARN/FAIL] Naming conventions
   - [PASS/WARN/FAIL] Architecture patterns
   - [PASS/WARN/FAIL] Import paths
   - [PASS/WARN/FAIL] Error handling
   - [PASS/WARN/FAIL] Security
   - [PASS/WARN/FAIL] Test coverage

   ### Issues Found
   - [list of issues, if any]

   ### Verdict: [READY TO PUSH / NEEDS FIXES]
   ```

6. **If issues are found**, list them clearly and ask the user if they want to fix them before pushing. If everything is clean, confirm it's safe to push.

$ARGUMENTS
