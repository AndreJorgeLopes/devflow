---
description: [devflow v0.1.0] Generate a session summary for Langfuse tracing — capture what happened, decisions made, and metrics for observability.
---

You are generating a session summary for observability via Langfuse.

## Steps

1. **Review the full session**. Analyze the conversation to extract:
   - **Goal**: What was the user trying to accomplish?
   - **Outcome**: Was it accomplished? Partially? Failed?
   - **Duration**: Approximate session length based on message count and complexity
   - **Scope**: How many files were touched, commands run, tools used?

2. **Catalog the actions taken**:
   - Files created, modified, or deleted
   - Commands executed and their results (pass/fail)
   - MCP tools invoked and their purposes
   - Decisions made during the session
   - Errors encountered and how they were resolved

3. **Assess session quality**:
   - **Efficiency**: Were there unnecessary detours or retries?
   - **Correctness**: Did the solution work on the first attempt?
   - **Process compliance**: Were the right skills/commands used?
   - **Memory usage**: Were relevant memories recalled? Were new learnings retained?

4. **Generate the structured summary**:

   ```
   ## Session Summary

   **Date:** <date>
   **Goal:** <what was the task>
   **Outcome:** <completed/partial/failed>
   **Session ID:** <generate a unique ID: YYYYMMDD-HHMM-<short-hash>>

   ### Actions
   | Action | Target | Result |
   |--------|--------|--------|
   | <action> | <file/command> | <pass/fail> |

   ### Decisions Made
   - <decision and rationale>

   ### Errors & Resolutions
   - <error>: <how it was resolved>

   ### Metrics
   - Files touched: <count>
   - Commands run: <count>
   - Tools invoked: <count>
   - Memories recalled: <count>
   - Learnings retained: <count>
   - Retries needed: <count>

   ### Quality Score
   - Efficiency: <1-5>
   - Correctness: <1-5>
   - Process compliance: <1-5>

   ### Tags
   <comma-separated tags for searchability: e.g., "feature", "bugfix", "messaging", "database">
   ```

5. **Log to Langfuse** if the Langfuse MCP tools are available. Use the appropriate Langfuse tracing tool to send:
   - The session summary as a trace
   - Key metrics as scored observations
   - Tags for filtering and search

   If Langfuse tools are not available, output the summary for the user to log manually.

6. **Present the summary** to the user and suggest:
   - Any learnings worth retaining (use `/reflect-session` for full reflection)
   - Process improvements for next time

## Important

- Be objective about quality scores. A session with many retries is not a 5/5 on efficiency.
- Include errors — they're the most valuable data for improving workflows.
- If the session was a quick question/answer with no significant actions, say so instead of generating a hollow summary.

$ARGUMENTS
