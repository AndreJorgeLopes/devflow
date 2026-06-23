---
description: [0.6.0] Spec a new feature — recall architecture knowledge, create a spec document, build an implementation plan, and break into tasks.
---

You are speccing a new feature. This command enforces a structured planning process before any code is written.

> **Diagram complexity** — before drawing, rate it:
> - 🟢 **simple** — linear / ≤4 nodes → plain ASCII is fine.
> - 🟡 **moderate** — fork-join, 5–8 nodes, or one crossing → OFFER a rendered Excalidraw (the **render-diagram** skill).
> - 🔴 **complex** — bidirectional, multi-lane, >8 nodes, or cycles → render with the **render-diagram** skill AND show it inline via the Read tool.

## Preamble (first action)

1. Detect ticket ID from `git branch --show-current` (regex `[A-Z]+-[0-9]+`); if none, use `none`.
2. Call `mark_chapter` with `{title: "Spec — <TICKET>", summary: "Writing the spec document"}`.
   If `mark_chapter` is unavailable (e.g. running outside Claude Code), skip silently.
3. Set terminal window title (CLI Claude Code only — silent no-op in Claude Desktop):
   ```bash
   [ -t 1 ] && printf '\e]2;%s — Spec\007' "<TICKET>" || true
   ```
   In Claude Desktop there is no controlling terminal — the visible phase signal comes from `mark_chapter` (step 2).

## Steps

1. **Parse the feature request** from the arguments below. Extract:
   - What the feature does (user-facing behavior)
   - Why it's needed (motivation, problem it solves)
   - Any constraints or requirements mentioned
   - If arguments are vague, ask clarifying questions before proceeding.
   - If the feature request has multiple valid interpretations, list them and ask the user to pick — don't silently commit to one.

2. **Recall architecture knowledge**. Use the Hindsight `recall` tool to retrieve:
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

   ## Acceptance Criteria

   - [ ] AC1: [observable behavior]
   - [ ] AC2: [observable behavior]
   - [ ] AC3: [edge case behavior]

   ## Non-goals

   Explicitly out of scope:
   - [thing we are NOT building]
   - [thing we are NOT refactoring]

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

   **Add an architecture diagram (optional but encouraged).** Unless the feature is trivial / non-architectural, generate a data-flow / architecture diagram for the feature via `/devflow:render-diagram`, saving the artefacts next to the spec in `docs/specs/` as `<feature-name>-architecture.excalidraw` + `.png` + `.svg`. Then:
   - **Read the PNG with the Read tool** during the session so the user sees the diagram inline (a markdown embed only shows clickable text in the Claude app).
   - **Embed it in the `## Architecture Impact` section** of the spec with a relative path:
     ```markdown
     ![<feature> architecture](./<feature-name>-architecture.png "<Feature> architecture")
     ```
   Skip gracefully (no diagram) if the feature is trivial or the render-diagram skill / its deps are unavailable.

5. **Break into tasks**. Convert the implementation plan into discrete, ordered tasks:
   - Each task should be completable in one session
   - Each task should have clear acceptance criteria
   - Tasks should be ordered by dependency (do X before Y)
   - Present as a numbered checklist

6. **Present the spec** to the user for review. Ask:
   - Does this match your intent?
   - Are there constraints I'm missing?
   - Is there a simpler approach we're missing?
   - Should we adjust the scope?

7. **Retain the architectural decisions** from this spec using the Hindsight `retain` tool, so they're available in future sessions.

8. **Hand off to the planning phase**. Invoke `devflow:phase-handoff` with arguments:
   - `--phase spec`
   - `--next-phase plan`

   The handoff skill writes a frozen-state file at `.devflow/state/<branch>/spec.md`, gates on a one-click `AskUserQuestion`, then spawns a new Claude Desktop session via `mcp__ccd_session__spawn_task` titled `[<TICKET>] [MR#<N>] Plan` (visible in the sidebar). The spawned session's initial prompt points it at the frozen-state file + spec absolute path and instructs it to invoke `/devflow:writing-plans` (the devflow plugin exposes that as a slash command).

   Do NOT auto-invoke `writing-plans` from this skill — context cleanup is the explicit boundary.

## Important

- Do NOT start implementation during this command. The output is a plan, not code.
- If the feature is too large, suggest splitting into multiple specs.
- Always check for existing similar features before designing from scratch.

$ARGUMENTS
