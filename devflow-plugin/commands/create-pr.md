---
description: [devflow v0.1.0] Full PR/MR creation pipeline — VCS-aware, self-review, code review checks, and PR creation with a structured template.
---

You are creating a pull request or merge request. This command runs the full pipeline and automatically uses the correct VCS CLI.

## Steps

1. **Gather PR context**. Run these commands to understand the full scope:

   ```bash
   git log --oneline main..HEAD
   git diff --stat main..HEAD
   git diff main..HEAD
   ```

   Also check the branch name for a ticket ID (e.g., `MES-1234`).

2. **Detect the VCS provider** from the git remote URL:

   ```bash
   git remote get-url origin
   ```

   Determine the provider:
   - Contains `github.com` → **GitHub**, use `gh pr create`
   - Contains `gitlab.com` or `gitlab.` → **GitLab**, use `glab mr create`
   - Other → manual PR creation (you will output the compare URL)

   Check that the required CLI tool is installed:
   - GitHub: `command -v gh` → if missing, tell user: "Install with: brew install gh"
   - GitLab: `command -v glab` → if missing, tell user: "Install with: brew install glab"

3. **Self-review the diff**. Read through the full diff and check for:
   - Leftover debug statements or TODOs
   - Missing error handling
   - Naming convention violations
   - Files that shouldn't be committed
   - Incomplete implementations or placeholder code
   - Missing tests for new functionality

4. **Run code review checks**:

   ```bash
   devflow check
   ```

   If devflow check is not available, run lint, type-check, and tests:

   ```bash
   yarn lint && yarn build && yarn test --changedSince=main
   ```

5. **If issues are found** in self-review or checks, report them and ask the user whether to fix them first or proceed anyway.

6. **Draft the PR/MR**. Analyze all commits and the full diff to create:
   - **Title**: Concise, conventional format (e.g., "feat(messaging): add retry logic for carrier timeouts")
   - **Summary**: 2-4 bullet points describing what changed and why
   - **Testing**: How the changes were tested
   - **Ticket**: Link to the ticket if a ticket ID is found

7. **Present the draft** to the user and wait for explicit approval before creating.

8. **Create the PR/MR** using the correct CLI:

   ### GitHub (`gh`)

   ```bash
   git push -u origin HEAD
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   ## Summary
   <bullet points>

   ## Changes
   <file-level description>

   ## Testing
   <how it was tested>

   ## Ticket
   <ticket link or N/A>

   ## Checklist
   - [ ] Tests pass
   - [ ] Lint passes
   - [ ] Types check
   - [ ] Self-reviewed
   EOF
   )"
   ```

   ### GitLab (`glab`)

   ```bash
   git push -u origin HEAD
   glab mr create --title "<title>" --description "$(cat <<'EOF'
   ## Summary
   <bullet points>

   ## Changes
   <file-level description>

   ## Testing
   <how it was tested>

   ## Ticket
   <ticket link or N/A>

   ## Checklist
   - [ ] Tests pass
   - [ ] Lint passes
   - [ ] Types check
   - [ ] Self-reviewed
   EOF
   )"
   ```

   ### Unknown provider

   If the provider is not recognized:
   1. Push the branch: `git push -u origin HEAD`
   2. Tell the developer to create the PR manually and output the compare URL in format: `https://<host>/<org>/<repo>/compare/<branch>`

9. **Return the PR/MR URL** to the user.

## Important

- Never create a PR/MR with failing checks unless the user explicitly approves it.
- Always push the branch before creating the PR/MR.
- If the diff is large (>500 lines), suggest splitting into smaller PRs.
- Use "PR" for GitHub and "MR" for GitLab in all user-facing text.

$ARGUMENTS
