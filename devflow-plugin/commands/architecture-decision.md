---
description: [devflow v0.1.0] Document an architectural decision — record the decision and rationale, retain into Hindsight, and update CLAUDE.md if needed.
---

You are documenting an architectural decision. This command ensures decisions are properly recorded and available for future recall.

## Steps

1. **Parse the decision** from the arguments below. If the arguments are brief, ask the user to elaborate on:
   - What was decided?
   - What alternatives were considered?
   - Why was this option chosen?
   - What are the tradeoffs?

2. **Structure the ADR** (Architecture Decision Record):

   ```
   ## ADR: <title>

   **Date:** <today's date>
   **Status:** Accepted
   **Context:** [What situation prompted this decision?]

   ### Decision
   [What was decided, stated clearly and concisely]

   ### Alternatives Considered
   1. **<Alternative A>**: [description] — Rejected because [reason]
   2. **<Alternative B>**: [description] — Rejected because [reason]

   ### Rationale
   [Why this approach was chosen over the alternatives]

   ### Consequences
   - **Positive**: [benefits]
   - **Negative**: [tradeoffs accepted]
   - **Risks**: [known risks]

   ### Implications
   - [What code/patterns must follow from this decision]
   ```

3. **Present the ADR** to the user for review and approval.

4. **Retain into Hindsight**. Use the `hindsight_retain` MCP tool to store the decision as a **Mental Model** or **Decision** memory:
   - Title: concise decision statement
   - Category: "Decision" or "Mental Model"
   - Content: the full ADR text
   - Context: the project/domain area affected

5. **Check if CLAUDE.md needs updating**. If the decision establishes a new hard rule or pattern that all future development must follow:
   - Read the current CLAUDE.md
   - Identify where the new rule fits
   - Propose the specific addition to the user
   - Only update CLAUDE.md if the user approves

6. **Confirm** what was recorded:

   ```
   ## Decision Recorded

   **Title:** <title>
   **Retained to Hindsight:** Yes
   **CLAUDE.md updated:** [Yes/No]

   This decision will be recalled automatically when working in the <affected area>.
   ```

## Important

- Every decision should have at least one alternative that was considered. If there were no alternatives, it's not really a decision — it's a constraint.
- Be honest about tradeoffs. Every decision has downsides.
- Only update CLAUDE.md for decisions that are true hard rules — things that must ALWAYS be followed.

$ARGUMENTS
