---
description: [devflow v0.1.0] Finish a feature — run verification, create PR/MR (VCS-aware), retain learnings, and hand off cleanup to the terminal.
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

4. **Check and update visualizations.** If this project has architecture visualizations, check if any need updating.

   First, check if a visualization directory exists:
   ```bash
   # Check common locations
   ls -d visualizations/ docs/visualizations/ docs/diagrams/ 2>/dev/null | head -1
   ```

   Also check for config:
   ```bash
   cat .devflow/visualizations.json 2>/dev/null || cat ~/.config/devflow/visualizations.json 2>/dev/null
   ```

   **If no visualization directory or config found:** Skip this step with a one-line note: "No visualization directory found, skipping visualization check."

   **If visualizations exist:**
   - Resolve the devflow root by running: `devflow root 2>/dev/null || readlink -f ~/.claude/commands/devflow | sed 's|/devflow-plugin/commands$||'`
   - Read the visualization skill for guidance: `Read <DEVFLOW_ROOT>/skills/visualizations/update-visualizations.md`
   - Analyze the full feature branch diff (`git diff main..HEAD` or `git diff master..HEAD`) to identify changes that affect architecture, workflows, or integrations
   - Read the visualization index (`<viz-path>/README.md`) and any potentially affected diagram files
   - Map changes to affected visualizations using the heuristics from the skill's Step 4
   - **If no diagrams need updating:** Say "No visualization updates needed" and move on
   - **If diagrams need updating:** Present a TLDR to the user:
     ```
     ## Visualization Updates Proposed

     **[diagram-file.md]:** <1-2 sentence gist of what would change>
     **[another-diagram.md]:** <1-2 sentence gist>

     Confirm to apply these updates, or skip to continue without changes.
     ```
   - **Wait for user confirmation** before making any changes
   - If confirmed: update the diagram files, then stage and commit:
     ```bash
     git add <viz-path>/
     git commit -m "docs: update visualizations for [brief feature description]"
     ```
   - Do NOT trigger first-run visualization setup (creating folders, README, defaults) inside this flow

   > **Note:** This step uses plain-text summaries since mermaid diagrams cannot be rendered in the terminal. Describe what was added, removed, or modified in each diagram.

5. **Resolve PR description strategy.** Determine which template to use for the PR/MR description:

   - Detect the project name:
     ```bash
     basename "$(git rev-parse --show-toplevel)"
     ```
   - Recall from Hindsight: query `"<project>: PR description strategy"` with tags `["pr-strategy"]`.
   - **If no stored strategy found:** Ask the user via `AskUserQuestion` with these options:
     - **Auto-generate (Recommended)** — Use devflow default template, fill sections from diff analysis.
     - **Use repo template** — Search codebase for PR/MR templates at standard locations.
     - **Custom path** — Specify a template file to use.
   - **If "Use repo template":** Search these locations using Glob:
     1. `.github/PULL_REQUEST_TEMPLATE.md`
     2. `.github/PULL_REQUEST_TEMPLATE/*.md`
     3. `.gitlab/merge_request_templates/*.md`
     4. `PULL_REQUEST_TEMPLATE.md` (root)
     5. `docs/pull_request_template.md`
     - If multiple found, use `AskUserQuestion` to pick one.
     - If none found, warn and fall back to auto-generate.
   - **If "Custom path":** Ask the user for the path, verify it exists with the Read tool.
   - Retain the choice via Hindsight: `retain("<project>: PR description strategy = <choice>", tags=["pr-strategy", "<project>"])`.
   - **If strategy is repo-template or custom:** Read the template file, parse its markdown headings (`##`, `###`) as section boundaries. Use these sections as the structure for the PR description in the next step instead of the default template. Preserve static content (checkboxes, boilerplate). Fill each section with content from the diff analysis. If a section can't be auto-filled, leave a `<!-- TODO: fill this -->` marker.
   - **If strategy is auto-generate:** Use the default devflow template structure (Summary/Changes/Testing/Ticket/Checklist).

   > **Note to agent:** The PR description strategy is now resolved. Use the determined template structure when generating the draft PR/MR description in the next step.

6. **CHECKPOINT — Diff review.** Before creating the PR/MR, present a summary of all changes for user approval:

   ```
   ## Ready to Create PR/MR

   **Branch:** <branch-name>
   **Base:** main (or master)
   **Commits:** <count> — <list of commit messages>
   **Files changed:** <count>
   **Lines:** +<added> / -<removed>

   ### Key changes
   <3-5 bullet points summarizing what's in the diff>

   ### Draft PR/MR title
   <proposed title>

   ### Draft PR/MR description
   <proposed description in markdown — use the template structure determined in step 5>
   ```

   **Wait for explicit user approval** ("looks good", "go ahead", "create it", etc.) before proceeding.

7. **Detect VCS provider and create PR/MR.** First detect the provider:

   ```bash
   git remote get-url origin
   ```

   - Contains `github.com` → GitHub, use `gh pr create`
   - Contains `gitlab.com` or `gitlab.` → GitLab, use `glab mr create`
   - Other → output compare URL for manual PR creation

   Push and create:

   ```bash
   git push -u origin HEAD
   ```

   ### GitHub (`gh`)
   ```bash
   gh pr create --title "<title>" --body "<body>"
   ```

   If `gh pr create` fails, retry once. If the second attempt also fails, surface the error to the user.

   ### GitLab (`glab`)
   ```bash
   glab mr create --title "<title>" --description "<body>"
   ```

   If `glab mr create` fails, check for a recovery file at `~/.config/glab-cli/recover/` and retry with `--recover`. If no recovery file exists or the retry also fails, surface the error to the user.

   Present the PR/MR URL to the user.

   > **CRITICAL: Do NOT stop after creating the PR/MR.** Steps 8-10 below are mandatory.
   > The feature is not complete until you have retained learnings, presented the summary,
   > and offered worktree cleanup. Continue immediately.

8. **Retain session learnings.** Review the session and retain important discoveries:
   - Architecture decisions made during this feature
   - Gotchas or non-obvious patterns encountered
   - Bug root causes and fixes
   - Use Hindsight `retain` for each learning, tagged with the project name

9. **Present the summary:**

   ```
   ## Feature Complete

   **Branch:** <branch-name>
   **PR/MR:** <url>
   **Commits:** <count>
   **Files changed:** <count>

   ### Checks
   - [PASS/FAIL] Lint
   - [PASS/FAIL] Types
   - [PASS/FAIL] Tests

   ### Learnings Retained
   - [list of retained memories]
   ```

10. **Offer worktree cleanup.** After the summary, ask the user via `AskUserQuestion`:

   - **Delete worktree now (Recommended)** — The branch is pushed to origin and the PR/MR is created. Removing the worktree is safe — it won't affect the PR/MR or the remote branch. The local branch reference is kept so you can re-create the worktree if you need to address review comments (`devflow worktree <branch-name>`).
   - **Keep for review feedback** — Leave the worktree intact in case you need to address PR/MR review comments. Run `devflow done <branch-name>` from your terminal when you're done.

   **If "Delete worktree now":**
   Tell the user you will now clean up the worktree and explain:

   > "The branch has been pushed to origin and the PR/MR exists on the remote — deleting the local worktree won't affect it. If you need to make changes later (e.g., review feedback), you can re-create the worktree with `devflow worktree <branch-name>`."

   First, determine the primary worktree path, move there, then remove:
   ```bash
   # Find the primary worktree (first entry = the original git clone)
   main_worktree="$(git worktree list --porcelain | grep '^worktree ' | head -1 | sed 's/^worktree //')"
   # Move out of the current worktree into the primary one
   cd "$main_worktree"
   # Ensure main branch isn't locked (detach if needed — git only allows one worktree per branch)
   git checkout --detach 2>/dev/null || true
   # Now safe to remove the feature worktree
   devflow done <branch-name>
   ```

   > **Why move first?** You cannot delete a worktree while your shell is inside it. Moving to the primary worktree first ensures `devflow done` can cleanly remove the directory and local branch.
   > **Why detach?** Git only allows one worktree per branch. If the primary worktree is on `main`, other worktrees can't reference it. Detaching frees the branch name without losing any files.

   **If "Keep for review feedback":**
   Tell the user:

   > "Worktree kept. When the PR/MR is merged, clean up with: `devflow done <branch-name>`"

## Important

- Never merge to `main` from inside the agent — use PRs.
- If checks fail, stop and help fix. Do not skip verification.
- Always retain learnings before ending the session.
- Use "PR" for GitHub repos and "MR" for GitLab repos in all user-facing text.
- Do NOT add a "Generated with Claude Code" or similar AI-attribution footer to the PR/MR description.
- The visualization check (step 4) is a lightweight pass — skip silently if no viz directory exists.

$ARGUMENTS
