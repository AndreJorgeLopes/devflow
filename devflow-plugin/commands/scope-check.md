---
description: "[devflow v0.1.0] Pre-implementation scope review — walk through ticket states, surface ambiguities, list assumptions, and draft clarifying questions before writing code."
---

You are about to start implementing a feature or task. Before writing any code, perform a structured scope check to surface gaps, ambiguities, and hidden complexity that could turn a 1-day task into a 4-day task.

**CRITICAL: User interaction rule.** Every time you need input from the user in this skill, you MUST use the `AskUserQuestion` tool. Never output a question as plain text and wait — always use the tool so the user gets a proper interactive prompt.

## Arguments

This skill accepts optional arguments via `$ARGUMENTS`:
- **First argument**: Ticket ID (e.g., `MES-3553`). If provided and a project management MCP is available, the ticket will be fetched automatically.
- **Remaining arguments**: Free-form context — ticket description, design links, or notes about the task.

If called from within the `new-feature` flow, ticket details and workspace context are already available — skip fetching and use the context passed to you.

## Steps

1. **Gather the task definition.** Use one of these sources (in priority order):
   - Ticket details already in context (if invoked from `new-feature` flow)
   - Fetch from project management MCP if a ticket ID is provided
   - `$ARGUMENTS` free text or user description

   If no task definition can be found, ask the user to describe the task before proceeding.

2. **Walk through every state.** For each requirement in the ticket/description, identify:
   - **Happy path** — what happens when everything works as expected?
   - **Edge cases** — null values, empty states, missing data, concurrent access
   - **Error states** — what can fail? What does the user see?
   - **Backwards compatibility** — will this break existing consumers/clients?

   Present findings in a table:

   ```
   | Area | What's specified | What's missing or ambiguous |
   |------|------------------|-----------------------------|
   | ...  | ...              | ...                         |
   ```

3. **List assumptions.** Write down everything you're inferring that the ticket doesn't explicitly state. Each assumption is a potential scope creep vector. Format:

   ```
   ### Assumptions
   - [assumption] — inferred from [evidence]
   - [assumption] — not mentioned, defaulting to [behavior]
   ```

4. **Check for design/spec completeness** (if designs or specs are linked):
   - Are all UI states covered (empty, loading, error, success)?
   - Are interactions specified (hover, click, keyboard)?
   - Does the design match existing patterns in the codebase, or does it introduce new ones?
   - Are there inconsistencies between the design and the ticket description?

   If designs are incomplete, note what's missing — don't guess.

5. **Identify dependencies and blockers:**
   - Are there subtasks or linked tickets that must land first?
   - Does this require API changes, schema changes, or config changes from another team?
   - Is there a feature flag or environment requirement?

6. **Assess scope vs estimate.** If the ticket has a size estimate (S/M/L or story points):
   - Does the scope match the estimate once you account for the gaps found above?
   - If not, flag it: "This is sized as S but the error handling + backwards compat concerns suggest M."

7. **Evaluate MR splitting.** Based on the gaps, dependencies, and scope found above, assess whether this ticket should be delivered as a single MR or split into multiple incremental MRs.

   **When to suggest splitting:**
   - The ticket has clearly independent pieces (e.g., schema change + UI change + logging)
   - The scope exceeds the estimate and splitting would bring each piece back in line
   - There are dependencies that block part of the work but not all of it
   - The ticket mixes concerns (backend + frontend, infra + feature)

   **When NOT to split:**
   - The ticket is small and cohesive — splitting would create unnecessary overhead
   - The pieces are tightly coupled and can't be tested independently

   **The golden rule: every MR must leave the project in a working state.** No MR should break builds, tests, or existing functionality — even temporarily. Each MR must be independently deployable and safe to merge without requiring follow-up MRs to fix what it broke.

   If splitting makes sense, propose a split plan:

   ```
   ### Proposed MR Split

   **MR 1: [title]** (can merge independently)
   - [what it includes]
   - [why it's safe on its own — e.g., "adds nullable field, existing code ignores it"]

   **MR 2: [title]** (depends on MR 1)
   - [what it includes]
   - [why it's safe on its own — e.g., "consumes the field, falls back gracefully if absent"]

   **MR 3: [title]** (optional follow-up)
   - [what it includes]
   - [why it can wait]

   Each MR is independently deployable and does not break existing functionality.
   ```

   For each proposed MR, verify:
   - Does the project build and pass tests with only this MR merged?
   - Does existing functionality continue to work?
   - Is there a graceful fallback if downstream MRs haven't landed yet?
   - Could this MR be the *only* one that ships and the project would still be fine?

   If any MR would leave the project in a broken state without a follow-up, it is **not a valid split**. Merge those pieces into one MR instead.

8. **Draft the clarifying message.** Compose a message the engineer can send to the PM, designer, or ticket creator. Structure:

   ```
   ### Clarifying Questions

   > I've reviewed [TICKET_ID] and have a few open questions before I start:
   >
   > 1. [question about ambiguity]
   > 2. [question about missing state]
   > 3. [question about dependency]
   >
   > I can start with [concrete parts] while we clarify these.
   > If [specific concern] turns out to be non-trivial, I'd suggest splitting it into a follow-up.
   ```

   Key principles for this message:
   - **Be specific** — "which error codes?" not "can you clarify errors?"
   - **Propose a path forward** — show you can unblock yourself on the clear parts
   - **Suggest scope splits early** — "I'd suggest a follow-up MR for X" prevents scope creep
   - **Stay neutral** — surface trade-offs, don't assign blame for gaps
   - If an MR split was proposed in step 7, include it in the message so the team is aligned on the delivery plan

9. **Present the full scope check** to the user. Format:

   ```
   ## Scope Check: [TICKET_ID or task name]

   **Ticket:** [title]
   **Size estimate:** [if available] | **Status:** [status]

   ### States & Gaps
   [table from step 2]

   ### Assumptions
   [list from step 3]

   ### Design/Spec Gaps
   [findings from step 4, or "N/A — no designs linked"]

   ### Dependencies & Blockers
   [findings from step 5, or "None identified"]

   ### Scope Assessment
   [finding from step 6]

   ### MR Strategy
   [split plan from step 7, or "Single MR — scope is cohesive and fits the estimate."]

   ### Draft Clarifying Message
   [message from step 8]
   ```

10. **Confirm MR strategy with the user.** Use `AskUserQuestion` to ask one of the following:

    **If step 7 proposed a split**, ask:
    > I've identified that this ticket can be split into [N] independent MRs (see the split plan above). Each MR is independently deployable and won't break the project. How would you like to proceed?

    Options:
    - **Split into [N] MRs** — Each MR will go through the full devflow lifecycle (brainstorm → implement → finish-feature with PR/MR creation). I'll orchestrate all of them.
    - **Single MR** — Deliver everything in one MR. Simpler workflow, larger review.
    - **Adjust the split** — Tell me how you'd like to group the work differently.

    **If step 7 did NOT propose a split** (scope is cohesive), ask:
    > Scope check complete. How would you like to proceed?

    Options:
    - **Start implementing** — Proceed to brainstorming and implementation.
    - **Send clarifying questions first** — Use the draft message above to align with the team before starting.
    - **Adjust scope/estimate** — Discuss scope changes before proceeding.

11. **If split was confirmed: choose execution strategy.** Use `AskUserQuestion` to ask:

    > How should I execute the [N] MRs?

    Options:
    - **Subagents (recommended for 2-3 MRs)** — I'll dispatch a subagent for each MR in the current session. Each subagent gets the full context and follows the complete devflow lifecycle ending with `devflow:finish-feature`. I'll coordinate and pass information between them.
    - **Agent-deck parallel sessions (recommended for 3+ MRs or long-running work)** — I'll create an agent-deck session for each MR. Each session runs independently with full context and follows the complete lifecycle. Visible in agent-deck TUI if you're running one.
    - **Sequential (manual)** — I'll work on one MR at a time in this session. After finishing each, I'll start the next.

12. **Store orchestration context.** Before dispatching any sub-tasks, store the full context that each sub-agent will need. This is critical — sub-agents must NOT need to re-fetch tickets or re-read files.

    Prepare a `SCOPE_CONTEXT` block containing:
    - Ticket ID, title, description, and all extracted details
    - The full scope check output (gaps, assumptions, dependencies)
    - The specific MR assignment for this sub-task (what it includes, what it does NOT include)
    - Branch naming convention: `feat/<ticket-id>/<mr-slug>` (e.g., `feat/MES-3553/graphql-schema`, `feat/MES-3553/message-fetching`)
    - Project name, base branch, and repo path
    - Any recalled Hindsight memories relevant to this work
    - The golden rule reminder: "Your MR must leave the project in a working state. Do not depend on other MRs to fix what yours breaks."

    Retain the split decision in Hindsight:
    ```
    retain("<project>: scope-check <ticket-id> — split into [N] MRs: [MR titles]. Strategy: [subagents|agent-deck|sequential]", tags=["<project>", "scope", "decision"])
    ```

    **Return the execution strategy and SCOPE_CONTEXT to the calling flow** (new-feature) so it can handle dispatching. If scope-check was invoked standalone (not from new-feature), proceed to dispatch directly using the patterns described in the new-feature command.

## Important

- This is a **prevention tool**, not a blocker. The goal is to surface risk early, not to create analysis paralysis.
- If the ticket is genuinely straightforward with no gaps, say so — "Scope check complete, no ambiguities found. Ready to proceed."
- Don't fabricate concerns. Only flag real gaps you've identified.
- The draft message should be ready to send — professional, neutral, and actionable.
- When called from `new-feature`, the output feeds back into the new-feature flow which handles dispatching.
- **Every user interaction MUST use `AskUserQuestion`** — never output a question as plain text.
- Retain significant scope findings in Hindsight: `retain("<project>: scope-check <ticket-id> — <key finding>", tags=["<project>", "scope", "decision"])`

$ARGUMENTS
