---
description: [devflow v0.1.0] Post-launch setup for a new feature worktree — detect ticket context, load task management data, recall memories, and transition to brainstorming.
---

You have been launched inside a feature worktree. Your job is to orient yourself, load ticket context, and start the feature.

**IMPORTANT:** Do NOT create worktrees or branches — that was already handled by `devflow worktree` before this session started.

## Arguments

This skill accepts optional arguments via `$ARGUMENTS`:
- **First argument**: Ticket ID (e.g., `MES-3716`, `LIN-42`, `#123`). If provided, the skill will auto-fetch ticket details from your project management tool.
- **Second argument**: Extra context or notes about the task (optional free text).

If no arguments are provided, the skill will try to auto-detect the ticket ID from the TMUX/agent-deck session name before falling back to workspace detection only.

## Steps

1. **Parse arguments.** Extract from `$ARGUMENTS`:
   - `TICKET_ID` — first word if it looks like a ticket ID (pattern: `[A-Z]+-\d+`, `#\d+`, or similar)
   - `EXTRA_CONTEXT` — everything after the ticket ID (if any)

   **If no ticket ID was found in arguments**, try to auto-detect from the environment:

   ```bash
   # Check if inside a TMUX session (agent-deck or plain tmux)
   tmux display-message -p '#{session_name}' 2>/dev/null
   ```

   - Parse the session name for a ticket pattern (`[A-Z]+-[0-9]+`)
   - Agent-deck sessions follow `agentdeck_<NAME>_<HASH>` — the ticket ID is in `<NAME>`
   - If a ticket ID is found, tell the user: "Detected ticket **<ID>** from session name. Using this unless you specify otherwise."
   - Set `TICKET_ID` to the detected value

2. **Detect workspace context.** Run these commands to understand where you are:

   ```bash
   git branch --show-current
   git log --oneline -1 main 2>/dev/null || git log --oneline -1 master 2>/dev/null
   basename "$(git rev-parse --show-toplevel)"
   ```

   Extract:
   - **Branch name** (e.g., `feat/MES-1234/add-user-metrics`)
   - **Base branch** (`main` or `master`)
   - **Project name** (from the repo root directory)
   - **Ticket ID** — use `TICKET_ID` from arguments if provided; otherwise try to parse from the branch name (e.g., `MES-1234` from `feat/MES-1234/...`)

   If the current branch is `main` or `master`, this skill does not apply — tell the user to create a worktree first with `devflow worktree <name>`.

3. **Detect project management MCP.** Check which project management tools are available to you in this session:

   - **Jira (Atlassian)**: Check if `mcp__claude_ai_Atlassian__getJiraIssue` is in your available tools
   - **Linear**: Check if any `mcp__linear__*` tools are available
   - **GitHub Issues**: Check if any `mcp__github__*` tools are available

   Determine `PM_TOOL` (one of: `jira`, `linear`, `github`, or `none`).

   **If no project management MCP is found (`PM_TOOL = none`):**
   - Inform the user: "No project management MCP detected. To get automatic ticket context, configure one of: Atlassian MCP (for Jira), Linear MCP, or GitHub MCP in your Claude Code settings."
   - Reference: "A future integration is planned (see SPIKE-kanban-board-integration in the devflow task backlog) for broader task management support."
   - Continue the skill using only workspace context and any `EXTRA_CONTEXT` provided in arguments.

4. **Fetch ticket details** (only if `TICKET_ID` is set AND `PM_TOOL != none`):

   ### For Jira (mcp__claude_ai_Atlassian__)

   Use `mcp__claude_ai_Atlassian__getJiraIssue` with the issue key.

   Extract from the response:
   - `summary` → ticket title
   - `description` → acceptance criteria or task description
   - `issuetype.name` → Bug / Story / Task / etc.
   - `priority.name` → priority level
   - `status.name` → current status
   - `assignee` → who it's assigned to
   - `labels` → any labels

   ### For Linear (mcp__linear__)

   Use whatever issue-fetching tool is available. Extract equivalent fields.

   ### For GitHub Issues (mcp__github__)

   Use the issues tool to fetch by issue number. Extract title, body, labels, assignee.

   **If fetching fails** (ticket not found, auth error, network error):
   - Warn the user: "Could not fetch ticket [TICKET_ID] from [PM_TOOL]. Continuing without ticket context."
   - Continue with workspace-only context.

5. **Recall relevant memories** using Hindsight. Query with:
   - `"<project>: <domain area from branch name>"`
   - `"<project>: architecture"` (general patterns)
   - If a ticket ID is present: `"<project>: <ticket-id>"`

6. **Present the workspace context:**

   ```
   ## Feature Workspace

   **Branch:** <branch-name>
   **Base:** <base-branch>
   **Project:** <project-name>
   **Ticket:** <ticket-id or "none">
   **PM Tool:** <jira | linear | github | none>

   ### Ticket Details
   <If ticket was fetched:>
   - **Title:** <ticket summary>
   - **Type:** <Bug / Story / Task>
   - **Priority:** <priority>
   - **Status:** <current status>
   - **Description:** <key points from description/acceptance criteria>

   <If no ticket context:>
   - No ticket context available. Describe the feature or provide a ticket ID as argument.

   ### Extra Context
   <EXTRA_CONTEXT if provided, otherwise omit this section>

   ### Recalled Context
   - [relevant memories, patterns, and gotchas for this area]
   - [or "No prior memories found for this area"]
   ```

7. **Suggest branch name** (if ticket was fetched and branch is still generic):

   If the current branch looks generic (e.g., just a ticket ID like `feat/MES-1234` with no description slug), suggest a descriptive branch name:
   - Format: `feat/<ticket-id>/<slugified-title>` (lowercase, hyphens, max 60 chars)
   - Example: `feat/MES-3716/extend-media-files-to-document-and-video`
   - Ask the user: "Would you like to rename the branch to `<suggested-name>`? (y/n)"
   - If yes: `git branch -m <suggested-name> && git push origin --delete <old-name> && git push -u origin <suggested-name>`

8. **Ask what the feature is about.** If ticket details were fetched, summarize your understanding and ask for confirmation or additional context. Otherwise, ask the user to describe the feature.

9. **Transition to brainstorming.** Once you understand the feature, invoke the `brainstorming` skill to explore requirements, design, and approach before writing any code.

## Important

- This skill is a **post-launch setup guide** — the worktree already exists.
- Always recall from Hindsight before starting work.
- Never skip the brainstorming step for non-trivial features.
- If the branch name contains a ticket ID, use it as a namespace prefix in all Hindsight interactions.
- If no project management MCP is available, don't block — continue with available context and note the limitation.
- Future: full task management board integration is tracked in `tasks/P3/SPIKE-kanban-board-integration.md`.

$ARGUMENTS
