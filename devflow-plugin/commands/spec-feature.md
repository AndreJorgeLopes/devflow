---
description: Spec a new feature — recall architecture knowledge, create a spec document, build an implementation plan, and break into tasks.
---

You are speccing a new feature. This command enforces a structured planning process before any code is written.

## Steps

1. **Parse the feature request** from the arguments below. Extract:
   - What the feature does (user-facing behavior)
   - Why it's needed (motivation, problem it solves)
   - Any constraints or requirements mentioned
   - If arguments are vague, ask clarifying questions before proceeding.

2. **Recall architecture knowledge**. Use the `hindsight_recall` MCP tool to retrieve:
   - Past architectural decisions related to this domain
   - Existing patterns used in similar features
   - Known gotchas in the affected area
   - Any hard rules that constrain the implementation

3. **Explore the existing codebase**. Identify:
   - Which layers of the architecture are affected (domain, application, infrastructure)
   - Existing code that this feature will interact with
   - Similar features already implemented that can serve as reference

4. **Write the spec document**. Create a file at `docs/specs/<feature-name>.md` with this structure:

   ```markdown
   # Feature: <name>

   ## Problem Statement

   [What problem does this solve?]

   ## Proposed Solution

   [High-level description of the approach]

   ## Architecture Impact

   - **Domain layer**: [changes needed]
   - **Application layer**: [changes needed]
   - **Infrastructure layer**: [changes needed]

   ## Technical Design

   [Detailed technical approach, including data models, API changes, etc.]

   ## Constraints & Decisions

   - [recalled hard rules that apply]
   - [architectural decisions that constrain the approach]

   ## Edge Cases

   - [edge case 1]
   - [edge case 2]

   ## Testing Strategy

   [How will this be tested?]

   ## Implementation Plan

   1. [step 1]
   2. [step 2]
      ...
   ```

5. **Break into tasks**. Convert the implementation plan into discrete, ordered tasks:
   - Each task should be completable in one session
   - Each task should have clear acceptance criteria
   - Tasks should be ordered by dependency (do X before Y)
   - Present as a numbered checklist

6. **Present the spec** to the user for review. Ask:
   - Does this match your intent?
   - Are there constraints I'm missing?
   - Should we adjust the scope?

7. **Retain the architectural decisions** from this spec using the `hindsight_retain` MCP tool, so they're available in future sessions.

## Important

- Do NOT start implementation during this command. The output is a plan, not code.
- If the feature is too large, suggest splitting into multiple specs.
- Always check for existing similar features before designing from scratch.

$ARGUMENTS
