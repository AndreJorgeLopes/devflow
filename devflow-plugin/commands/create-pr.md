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

6. **Resolve PR description strategy**.

   - Detect the project name:

     ```bash
     basename "$(git rev-parse --show-toplevel)"
     ```

   - Recall from Hindsight: query `"<project>: PR description strategy"` with tags `["pr-strategy"]`.

   - **If no stored strategy found:** Ask the user via `AskUserQuestion` with these options:
     - **Auto-generate (Recommended)** — Use devflow default template, fill sections from diff analysis
     - **Use repo template** — Search codebase for PR/MR templates at standard locations
     - **Custom path** — Specify a template file to use

   - **If "Use repo template":** Search these locations using Glob:
     1. `.github/PULL_REQUEST_TEMPLATE.md`
     2. `.github/PULL_REQUEST_TEMPLATE/*.md`
     3. `.gitlab/merge_request_templates/*.md`
     4. `PULL_REQUEST_TEMPLATE.md` (root)
     5. `docs/pull_request_template.md`
     - If multiple found → `AskUserQuestion` to pick one
     - If none found → warn and fall back to auto-generate

   - **If "Custom path":** Ask for the path, verify it exists with Read tool.

   - Retain the choice via Hindsight: `retain("<project>: PR description strategy = <choice>", tags=["pr-strategy", "<project>"])`.

   - **If strategy is repo-template or custom:** Read the template file, parse its markdown headings (`##`, `###`) as section boundaries. Use these sections as the structure for the PR description in the next step instead of the default template. Preserve static content (checkboxes, boilerplate). Fill each section with content from the diff analysis. If a section can't be auto-filled, leave a `<!-- TODO: fill this -->` marker.

   - **If strategy is auto-generate:** Use the default devflow template structure (Summary/Changes/Testing/Ticket/Checklist).

   - Note: The PR description strategy is now resolved. Use the determined template structure when generating the draft PR/MR description in the next step.

7. **Draft the PR/MR**. Analyze all commits and the full diff to create the description using the template structure resolved in step 6. For **auto-generate** mode, use the default sections below. For **repo-template** or **custom** mode, use the parsed sections from the template file instead.

   Default sections (auto-generate fallback):
   - **Title**: Concise, conventional format (e.g., "feat(messaging): add retry logic for carrier timeouts")
   - **Summary**: 2-4 bullet points describing what changed and why
   - **Testing**: How the changes were tested
   - **Ticket**: Link to the ticket if a ticket ID is found

8. **Present the draft** to the user and wait for explicit approval before creating.

9. **Create the PR/MR** using the correct CLI:

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

   If `gh pr create` fails, retry the command once.
   If the retry also fails, surface the error to the user.

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

   If this fails with a 401 or other error:
   1. Check if a recovery file exists (glab creates one at `~/.config/glab-cli/recover/`)
   2. If yes, retry with: `glab mr create --recover`
   3. If no recovery file, or the retry also fails, surface the error to the user

   ### Unknown provider

   If the provider is not recognized:
   1. Push the branch: `git push -u origin HEAD`
   2. Tell the developer to create the PR manually and output the compare URL in format: `https://<host>/<org>/<repo>/compare/<branch>`

10. **Return the PR/MR URL** to the user.

## Important

- Never create a PR/MR with failing checks unless the user explicitly approves it.
- Always push the branch before creating the PR/MR.
- If the diff is large (>500 lines), suggest splitting into smaller PRs.
- Use "PR" for GitHub and "MR" for GitLab in all user-facing text.
- Do NOT add a "Generated with Claude Code" or similar AI-attribution footer to the PR/MR description.

$ARGUMENTS
