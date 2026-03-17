---
description: Find the best ROI task in a Jira Epic — highest story points for least effort, filtered to unassigned To Do tasks only.
---

You are analyzing a Jira Epic to find the task with the best return on investment (highest story points relative to effort/size) that is available to pick up.

## Inputs

Provide via `$ARGUMENTS`:
- **Epic URL or key** — e.g., `https://aircall-product.atlassian.net/browse/MES-3548` or just `MES-3548`

Example: `/devflow:best-roi-task https://aircall-product.atlassian.net/browse/MES-3548`

If no argument is provided, ask the user for the Epic URL or key.

## Steps

1. **Parse the Epic key.** Extract from the argument:
   - If URL: parse the key from the path (e.g., `MES-3548` from `.../browse/MES-3548`)
   - If already a key (matches `[A-Z]+-\d+`): use directly

2. **Fetch all child issues** using Jira MCP:

   Use `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` with:
   - `cloudId`: the Atlassian site URL from the epic URL, or default to `aircall-product.atlassian.net`
   - `jql`: `"Epic Link" = <EPIC_KEY> ORDER BY created ASC`
   - `fields`: `["summary", "status", "assignee", "customfield_10028", "customfield_10188", "issuetype", "issuelinks"]`
   - `maxResults`: 50

3. **Analyze blockers.** For each task, inspect `issuelinks` for "Blocks" relationships:
   - Look for links where `type.name` is `"Blocks"` and the task appears in `outwardIssue` (meaning another issue blocks it) — specifically, links with `type.inward` = `"is blocked by"` where the current task is the inward side.
   - In practice: check for links where `inwardIssue.key` matches the current task (the current task "is blocked by" the `outwardIssue`), OR where `outwardIssue` exists and `type.outward` = `"blocks"` (meaning the linked issue blocks the current task).
   - For each blocker found, note its key and status.
   - A task is **unblocked** if it has no blockers, OR all its blockers are in status category `"done"` or status name `"In Code Review"` or later (i.e., `statusCategory.key` is `"done"` or status name contains "Review").

4. **Filter to eligible tasks.** Only include tasks where:
   - `assignee` is `null` (unassigned)
   - `status.statusCategory.key` is `"new"` (To Do) — this catches any status name that maps to the "To Do" category
   - The task is **unblocked** (no blockers, or all blockers are done / in code review)

   Tasks that match the first two criteria but ARE blocked should be shown separately (see step 6).

5. **Calculate ROI score** for each eligible task:

   Map t-shirt size (`customfield_10188.value`) to effort:
   | Size | Effort |
   |------|--------|
   | XS   | 1      |
   | S    | 2      |
   | M    | 3      |
   | L    | 5      |
   | XL   | 8      |

   Story points come from `customfield_10028`.

   **ROI score** = `story_points / effort`. If story points are null/0, score is 0.

6. **Present results** sorted by ROI score descending:

   ```
   ## Best ROI Tasks in <EPIC_KEY>

   | Rank | Task | Summary | Points | Size | ROI Score | Blocked By |
   |------|------|---------|--------|------|-----------|------------|
   | 1    | ...  | ...     | ...    | ...  | ...       | — (or blocker key + status) |

   ### Recommendation
   **<TASK_KEY>** — "<summary>" — <points> points, size <size> (ROI: <score>)
   ```

   The **Blocked By** column shows:
   - `—` if the task has no blockers
   - `<KEY> (Done)` or `<KEY> (In Code Review)` if it had blockers but they're all resolved/nearly resolved

   If no eligible tasks are found, report:
   > No unassigned To Do tasks found in epic <EPIC_KEY>. All tasks are either assigned, in progress, or blocked.

7. **Show blocked tasks** that would otherwise be eligible (unassigned + To Do) but have unresolved blockers:

   ```
   ### Blocked tasks (unassigned, To Do, but blocked)
   | Task | Summary | Points | Size | Blocked By |
   |------|---------|--------|------|------------|
   | ...  | ...     | ...    | ...  | <KEY> (<status>) |
   ```

   This helps the user see what's coming next once blockers clear.

8. **Show other non-eligible tasks** (assigned or in progress) for the full picture:

   ```
   ### Other tasks (assigned or in progress)
   | Task | Summary | Points | Size | Status | Assignee |
   ```

## Important

- Only recommend tasks that are **unassigned AND in To Do status AND unblocked**. Tasks that are assigned, in progress, in code review, done, or blocked are excluded from the ROI ranking.
- A blocker is considered resolved if its status is "Done" or "In Code Review" (or any status in the `done` category). Only tasks with ALL blockers resolved count as unblocked.
- If multiple tasks have the same ROI score, prefer the one with more story points (higher absolute value).
- The `customfield_10028` field is story points and `customfield_10188` is t-shirt size — these are Jira custom field IDs specific to the Aircall Jira instance. Other instances may use different field IDs.
- Blocker relationships use the "Blocks" link type in Jira. The `issuelinks` field contains both inward and outward links — check for links where the current task is blocked by another issue.

$ARGUMENTS
