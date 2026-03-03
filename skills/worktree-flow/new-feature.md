---
description: Start a new feature — create a worktree via Worktrunk, recall relevant memories, and set up the workspace.
---

You are starting a new feature. This command sets up an isolated workspace with full context.

## Steps

1. **Parse the feature details** from the arguments below. Extract:
   - Feature name or ticket ID (e.g., "MES-1234" or "add-user-metrics")
   - Brief description of what the feature does
   - If no arguments provided, ask the user for a feature name and description.

2. **Create the worktree** using Worktrunk. Run:

   ```bash
   worktrunk new <feature-name>
   ```

   This creates an isolated git worktree branched from the main branch. If `worktrunk` is not available, fall back to manual git worktree creation:

   ```bash
   git worktree add ../worktrees/<feature-name> -b feat/<feature-name>
   ```

3. **Recall relevant memories** for this feature area. Use the `hindsight_recall` MCP tool with:
   - The feature description as the query
   - Any mentioned domain areas (e.g., "messaging", "conversations", "carriers")
   - Any mentioned technologies or patterns

4. **Present the workspace setup**:

   ```
   ## Feature Workspace Ready

   **Feature:** <feature-name>
   **Branch:** feat/<feature-name>
   **Worktree:** <path>

   ### Recalled Context
   - [relevant memories, patterns, and gotchas for this area]

   ### Suggested Starting Points
   - [files likely to be modified based on the feature description]
   - [related test files]

   ### Reminders
   - [any hard rules from memory that apply]
   ```

5. **Suggest next steps**:
   - Use `/spec-feature` if the feature needs a spec first
   - Dive into implementation if the scope is clear
   - Review recalled architecture decisions that might constrain the approach

## Important

- Always create the worktree BEFORE starting any code changes. This keeps the main workspace clean.
- If the feature name matches a ticket ID pattern, use it as the branch prefix (e.g., `feat/MES-1234/description`).
- The worktree is disposable — it will be cleaned up by `/finish-feature`.

$ARGUMENTS
