---
description: Mark a devflow task as done — update status, move to done/ folder, and retain learnings.
---

You are completing a task from the devflow task backlog. This skill handles the lifecycle transition from in-progress/open to done.

## Inputs

Provide via `$ARGUMENTS`:
- **Task ID** — the task filename without extension (e.g., `FEAT-git-platform-resolve-repo`, `ARCH-pr-creation-vcs-detection`)

If no task ID is provided, try to infer from the current branch name or ask the user.

## Steps

1. **Find the task file.** Search across all priority folders:

   ```bash
   find /Users/andrejorgelopes/dev/devflow/tasks -name "<TASK_ID>.md" -not -path "*/done/*"
   ```

   If not found, check if it's already in `done/` and inform the user.

2. **Update the task status.** In the frontmatter, change:
   ```yaml
   status: done
   ```

3. **Move to done/ folder:**

   ```bash
   mkdir -p /Users/andrejorgelopes/dev/devflow/tasks/done
   mv /Users/andrejorgelopes/dev/devflow/tasks/<priority>/<TASK_ID>.md /Users/andrejorgelopes/dev/devflow/tasks/done/
   ```

4. **Retain learnings.** Use Hindsight to retain what was learned from completing this task:

   ```
   retain("devflow: completed <TASK_ID> — <brief summary of what was done and key decisions>", tags=["devflow", "task-complete"])
   ```

5. **Report completion:**

   ```
   ## Task Completed

   **Task:** <TASK_ID>
   **Title:** <task title from frontmatter>
   **Was in:** <priority folder it came from>
   **Moved to:** tasks/done/
   **Learnings retained:** yes/no
   ```

## Important

- Always update the `status` field in frontmatter before moving.
- The `done/` folder is the single source of truth for completed tasks.
- If the task has `depends_on` entries, do NOT check dependents — that's the responsibility of whoever picks up the next task.

$ARGUMENTS
