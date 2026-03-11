# Devflow Project Instructions

## Skill Interaction Rules

### MANDATORY: Use `AskUserQuestion` for all user choices

When any skill or command needs to present choices, confirmations, or selections to the user,
you **MUST** use the `AskUserQuestion` tool instead of printing a text question and waiting
for input. This applies to:

- Yes/No confirmations (e.g., "Want me to launch via agent-deck?")
- Multiple choice selections (e.g., "Which group?", "Which template?")
- Approval gates (e.g., "Proceed with these changes?")

**Why:** Text-based questions create a poor UX — the user sees a wall of text and has to
type a free-form response. `AskUserQuestion` provides clickable options, is faster to
answer, and prevents misinterpretation.

**Exception:** Open-ended questions where the user needs to provide free text (e.g.,
"Describe the feature") should still use normal text output, since `AskUserQuestion`
is designed for structured choices.
