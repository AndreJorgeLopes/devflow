---
description: Full PR creation pipeline — self-review, Continue.dev checks, and PR creation with a structured template.
---

You are creating a pull request. This command runs the full PR pipeline.

## Steps

1. **Gather PR context**. Run these commands to understand the full scope:

   ```bash
   git log --oneline main..HEAD
   git diff --stat main..HEAD
   git diff main..HEAD
   ```

   Also check the branch name for a ticket ID (e.g., `MES-1234`).

2. **Self-review the diff**. Read through the full diff and check for:
   - Leftover debug statements or TODOs
   - Missing error handling
   - Naming convention violations
   - Files that shouldn't be committed
   - Incomplete implementations or placeholder code
   - Missing tests for new functionality

3. **Run Continue.dev checks**:

   ```bash
   cn check
   ```

   If `cn` is not available, run lint, type-check, and tests:

   ```bash
   yarn lint && yarn build && yarn test --changedSince=main
   ```

4. **If issues are found** in self-review or checks, report them and ask the user whether to fix them first or proceed anyway.

5. **Draft the PR**. Analyze all commits and the full diff to create:
   - **Title**: Concise, conventional format (e.g., "feat(messaging): add retry logic for carrier timeouts")
   - **Summary**: 2-4 bullet points describing what changed and why
   - **Testing**: How the changes were tested
   - **Ticket**: Link to the ticket if a ticket ID is found

6. **Present the PR draft** to the user for review and approval.

7. **Create the PR** using GitHub CLI:

   ```bash
   git push -u origin HEAD
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   ## Summary
   <bullet points>

   ## Changes
   <file-level description of changes>

   ## Testing
   <how it was tested>

   ## Ticket
   <ticket link or N/A>

   ## Checklist
   - [ ] Tests pass
   - [ ] Lint passes
   - [ ] Types check
   - [ ] Self-reviewed
   - [ ] CLAUDE.md compliance verified
   EOF
   )"
   ```

8. **Return the PR URL** to the user.

## Important

- Never create a PR with failing checks unless the user explicitly approves it.
- Always push the branch before creating the PR.
- If the diff is large (>500 lines), suggest splitting into smaller PRs.

$ARGUMENTS
