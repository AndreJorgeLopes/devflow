---
description: Deep codebase walkthrough before implementation — trace the full flow, explain architecture, and build understanding.
---

Guide the user through a deep technical walkthrough of the codebase areas affected by their task, BEFORE any implementation begins. This builds architectural understanding so the user can meaningfully review code during implementation.

**When to use:** Before brainstorming/implementation, when the user wants to understand what they're about to build and how the existing system works. Especially valuable when the user hasn't worked in this part of the codebase before.

## Steps

1. **Gather the task context.** Read the ticket (Jira, Linear, etc.) and recall relevant memories from Hindsight:

   ```
   recall("<project>: <topic from ticket>")
   recall("<project>: architecture")
   ```

   Extract: what the task changes, which repos/services are involved, what domain concepts are at play.

2. **Trace the end-to-end flow.** Map the complete journey from user action to final effect. Show it as a diagram first (ASCII art), then walk through each leg:

   - Start with the **main flow** (happy path from trigger to outcome)
   - Then show **side effects** branching off the main flow (observability, billing events, push notifications, data platform events, etc.)
   - For each leg: name the service, the function, the file path, and what data moves between them

   **CRITICAL:** Show EVERY step including database persistence, queue publishing, and downstream consumers. Do NOT skip the "obvious" steps — they are not obvious to someone learning the codebase.

3. **Show the actual code.** For each leg of the flow, show:

   - The exact file path and line numbers
   - The key function signature or code block (not the entire file — just the relevant 5-20 lines)
   - What goes IN (parameters/payload) and what comes OUT (return value/event)

   When describing a service's role, be precise: say "receives and delivers" for pass-through services, not "stores and processes" (which implies data duplication). Define domain terms on first use.

4. **Identify what changes.** Map the task's changes onto the flow:

   - Which legs of the flow are affected?
   - Which files need modification?
   - What's the before/after for the data shape?

5. **Create a "files to read" list.** Prioritized list of files the user should read to understand the implementation. Only include files that are:

   - (a) Directly modified by the implementation, OR
   - (b) Essential context (explicitly mark these as "context only — no changes needed")

   Do NOT list files that are merely adjacent or tangentially related.

6. **List assumptions and open questions.** For each assumption:

   - State what you believe to be true
   - Verify it against the ticket, Confluence docs, or codebase — do NOT present unverified assumptions as facts
   - If you can't verify, say "I need to verify this" and check

7. **Present the walkthrough.** Structure it so it takes ~30 minutes to read:

   - Lead with the big-picture diagram
   - Walk through each leg with code
   - End with the files-to-read list and assumptions
   - Ask the user if anything is unclear before proceeding

8. **Retain the architectural knowledge** in Hindsight for future sessions:

   ```
   retain("<project>: <flow description and key files>", tags=["<project>", "architecture"])
   ```

## Walkthrough Quality Checklist

Before presenting, verify:
- [ ] Every step in the flow has actual code shown (especially DB persistence)
- [ ] Side effects (events, observability, billing) are explicitly shown branching off the main flow
- [ ] Domain terms are defined on first use
- [ ] No files listed as "worth reading" that aren't relevant to implementation
- [ ] All assumptions are verified against tickets/docs, not guessed
- [ ] Data storage vs pass-through is precisely described for each service

## Important

- This skill is about UNDERSTANDING, not implementation. Do not write or propose code changes.
- Tailor depth to the user's familiarity. If they've worked in this area before, focus on what's new. If it's their first time, cover the fundamentals.
- Show the flow visually first (diagram), then drill into code. Visual learners need the map before the details.
- Always check for local testing capabilities before suggesting remote/staging testing.
- If the user asks questions during the walkthrough, these are signals of knowledge gaps — fill them thoroughly, then note what you should have covered proactively.

$ARGUMENTS
