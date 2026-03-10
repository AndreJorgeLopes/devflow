---
description: [devflow v0.1.0] Reflect on the current session, extract learnings, and consolidate them into Hindsight for future recall.
---

You are wrapping up a session. Reflect on what happened and consolidate the valuable learnings.

## Steps

1. **Review the session**. Look back through the conversation and identify:
   - What was the original task or goal?
   - What approach was taken?
   - What worked well?
   - What didn't work or required correction?
   - Were there any surprises or non-obvious findings?
   - Were any decisions made? What was the rationale?

2. **Extract learnings**. For each meaningful insight, classify it:
   - **Mental Model** — a reusable pattern discovered
   - **Hard Rule** — a constraint identified the hard way
   - **Gotcha** — a pitfall encountered
   - **Decision** — a choice made with rationale worth preserving
   - **Technique** — a method that proved effective
   - **Discovery** — something new learned about a tool or system

3. **Present the learnings** to the user for review:

   ```
   ## Session Reflection

   **Task:** [what was accomplished]
   **Duration:** [approximate session length]

   ### Learnings to Retain

   1. [Category] **Title**: Description
   2. [Category] **Title**: Description
   ...

   ### Decisions Made
   - [decision and rationale]

   ### Open Questions
   - [anything unresolved]
   ```

4. **Ask the user** which learnings to retain. Default is all of them unless the user removes some.

5. **Retain each approved learning** using the Hindsight `retain` tool. Store each one individually with proper categorization.

6. **Confirm** the number of memories retained and list their titles.

## Important

- Be honest about what went wrong. Mistakes are the most valuable learnings.
- Don't retain trivial things. Focus on insights that will save time in future sessions.
- If the session was straightforward with no notable learnings, say so — don't force it.

$ARGUMENTS
