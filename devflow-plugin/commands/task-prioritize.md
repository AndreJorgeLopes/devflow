---
description: [devflow v0.1.0] Reprioritize a devflow task — move between priority folders (P0-P4) and update frontmatter.
---

You are reprioritizing a task in the devflow task backlog.

## Inputs

Provide via `$ARGUMENTS`:
- **Task ID** — the task filename without extension
- **New priority** — one of: `P0`, `P1`, `P2`, `P3`, `P4`

Example: `/devflow:task-prioritize FEAT-context-compaction-skill P1`

If arguments are missing, ask the user for both.

## Steps

1. **Find the task file:**

   ```bash
   find /Users/andrejorgelopes/dev/devflow/tasks -name "<TASK_ID>.md" -not -path "*/done/*"
   ```

2. **Update frontmatter.** Change the `priority` field:
   ```yaml
   priority: <NEW_PRIORITY>
   ```

3. **Move to the correct folder:**

   ```bash
   mkdir -p /Users/andrejorgelopes/dev/devflow/tasks/<NEW_PRIORITY>
   mv /Users/andrejorgelopes/dev/devflow/tasks/<OLD_PRIORITY>/<TASK_ID>.md /Users/andrejorgelopes/dev/devflow/tasks/<NEW_PRIORITY>/
   ```

4. **Report the change:**

   ```
   ## Task Reprioritized

   **Task:** <TASK_ID>
   **Title:** <task title>
   **From:** <old priority>
   **To:** <new priority>
   ```

## Important

- Never move tasks from `done/` — completed tasks stay completed.
- If the task is already at the requested priority, inform the user and do nothing.

$ARGUMENTS
