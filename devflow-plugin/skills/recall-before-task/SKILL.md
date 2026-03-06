---
name: recall-before-task
description: Recall relevant memories from Hindsight before starting a task. Injects past learnings, decisions, and context into the current session.
---

You are about to start a task. Before doing anything else, recall relevant memories so you have full context.

## Steps

1. **Parse the task description** from the arguments below. Identify the key topics, technologies, file paths, and domain concepts mentioned.

2. **Recall memories** using the Hindsight MCP tools. Make multiple recall calls to cover different aspects:
   - Use the `hindsight_recall` MCP tool with the full task description as the query.
   - If the task mentions specific files or modules, make an additional recall for those paths.
   - If the task mentions a domain concept (e.g., "authentication", "worktrees", "CI pipeline"), recall for that concept.

3. **Synthesize retrieved memories** into a brief context block. Organize by relevance:
   - **Hard rules** — constraints or decisions that MUST be followed
   - **Relevant patterns** — past approaches that worked well in this area
   - **Gotchas** — past mistakes or edge cases to watch out for
   - **Related decisions** — architectural decisions that affect this task

4. **Present the context** to the user in a concise summary before proceeding with the task. Format:

   ```
   ## Recalled Context for This Task

   **Hard Rules:**
   - [rule]

   **Relevant Patterns:**
   - [pattern]

   **Gotchas:**
   - [gotcha]

   **Related Decisions:**
   - [decision]
   ```

5. **Ask the user** if they want to proceed with the task now, or if there's additional context to consider.

## Important

- Do NOT skip the recall step even if the task seems simple. Past context prevents repeated mistakes.
- If no memories are retrieved, say so explicitly — "No prior memories found for this area."
- Do not fabricate memories. Only present what Hindsight actually returns.

$ARGUMENTS
