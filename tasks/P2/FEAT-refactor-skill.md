---
id: FEAT-refactor-skill
title: "Refactor Skill (Multi-Agent Refactoring)"
priority: P2
category: features
status: open
depends_on: []
estimated_effort: XL
files_to_touch:
  - devflow-plugin/commands/refactor.md
  - skills/registry.json
---

# Refactor Skill (Multi-Agent Refactoring)

## Context

Refactoring is one of the most complex and error-prone tasks agents perform. A single-pass "refactor this file" approach often leads to broken imports, missed callers, incomplete migrations, and regressions. By decomposing refactoring into distinct phases — documentation, planning, prompt generation, execution, and review — each phase can be handled by a specialized sub-agent with focused context, reducing errors and improving quality.

## Problem Statement

1. **Refactoring without documentation fails**: Agents refactor files without understanding how they fit into the broader architecture, leading to broken dependencies
2. **Plans and execution are conflated**: Agents jump into code changes without a reviewed plan, making it hard to catch design issues before they're implemented
3. **Single-agent context overload**: Large refactors exhaust the context window with both analysis AND implementation, degrading quality in later steps
4. **No structured review**: Post-refactor review is ad-hoc — there's no systematic check that the refactor preserved behavior and didn't break callers

## Desired Outcome

- A `/devflow:refactor` command that orchestrates a multi-phase refactoring workflow
- Each phase runs in a sub-agent with focused context and a specific deliverable
- The user reviews the plan BEFORE any code changes are made
- Tests are run after each incremental change during execution
- A final review sub-agent validates the complete refactor

## Implementation Guide

### Step 1: Create the `/devflow:refactor` skill command

Create `devflow-plugin/commands/refactor.md`:

```markdown
---
name: refactor
description: Multi-phase refactoring workflow with sub-agents for documentation, planning, execution, and review
arguments: file path(s) to refactor + optional description
---

# Multi-Agent Refactoring Workflow

## Input

- `$ARGUMENTS`: File path(s) to refactor, optionally followed by a description of the desired refactoring
- Example: `src/services/auth.ts — Extract token validation into a separate module`

## Phase 1: Documentation Generation (Sub-Agent 1)

**Goal:** Produce a comprehensive understanding document for the target file(s).

Spawn a sub-agent with this prompt:
```

Analyze the file(s) at <file-paths> and produce a documentation report covering:

1. **Imports**: What this file imports and from where
2. **Exports**: What this file exports (functions, types, constants, classes)
3. **Callers**: Which files in the codebase import from this file (use grep/glob to find all import statements referencing this file)
4. **Callees**: Which external functions/services this file calls
5. **Architecture role**: Where this file sits in the project architecture (domain, application, infrastructure, etc.)
6. **Domain concepts**: What business/domain concepts this file implements
7. **Test coverage**: Which test files cover this code and what they test
8. **Coupling assessment**: How tightly coupled is this file to its callers/callees

Output the documentation as a structured markdown document.
Do NOT suggest any changes — only document what exists.

```

Save output to a temporary file: `~/.devflow/refactor/<session-id>/01-documentation.md`

**Present documentation to user for review before proceeding.**

## Phase 2: Refactoring Plan (Sub-Agent 2)

**Goal:** Create a detailed step-by-step plan without writing any code.

Spawn a sub-agent with:
- Input: The documentation from Phase 1 + the file content + the refactoring description
- Prompt:

```

Given this documentation and file content, create a detailed refactoring plan for: <refactoring-description>

The plan must include:

1. **Summary**: What changes and why (1-2 sentences)
2. **Steps**: Numbered list of atomic changes, each step being independently committable:
   - What file to modify
   - What to add/remove/change
   - Why this change is needed
3. **Impact on callers**: For each caller identified in the docs, what changes they need
4. **Backward compatibility**: Can this be done without breaking existing callers? If not, what's the migration path?
5. **Test changes**: Which tests need updating, which new tests are needed
6. **Risk assessment**: What could go wrong? Edge cases to watch for.
7. **Execution order**: In what order should the steps be performed to minimize breakage?

Do NOT write any code — only describe what to do.

```

Save output to: `~/.devflow/refactor/<session-id>/02-plan.md`

**Present plan to user for review and approval before proceeding.**
If the user requests changes to the plan, iterate before moving on.

## Phase 3: Prompt Generation (Sub-Agent 3)

**Goal:** Convert the plan into precise, standalone prompts for execution.

Spawn a sub-agent with:
- Input: Documentation + Plan + File content
- Prompt:

```

Convert this refactoring plan into a series of precise, standalone prompts that an AI coding agent can execute one at a time.

For each step in the plan, generate a prompt that:

1. States exactly what to do (file path, function name, line range if relevant)
2. Provides the context needed (don't assume the executor has read the plan)
3. Specifies the expected outcome
4. Includes a verification step (what command to run to confirm success)
5. Is independent — can be understood without reading other prompts (include necessary context)

Format each prompt as:

### Step N: <title>

**File(s):** <paths>
**Action:** <what to do>
**Context:** <why, and what to be careful of>
**Verification:** <command or check to confirm success>

```

Save output to: `~/.devflow/refactor/<session-id>/03-prompts.md`

## Phase 4: Execution (Current Session)

**Goal:** Execute each prompt sequentially, running tests after each change.

For each prompt generated in Phase 3:
1. Read the prompt
2. Execute the described change
3. Run the project's test suite (or targeted tests for affected files)
4. If tests pass: move to next prompt
5. If tests fail: diagnose and fix before proceeding
6. After each successful step, consider committing (atomic commits)

**Important:** If a step fails repeatedly (3+ attempts), STOP and present the issue to the user.

## Phase 5: Review (Sub-Agent 4)

**Goal:** Comprehensive review of all changes made during execution.

Spawn a sub-agent with:
- Input: Git diff of all changes + original documentation + original plan
- Prompt:

```

Review this refactoring for correctness and completeness:

1. **Plan adherence**: Were all planned steps executed? Any deviations?
2. **Behavioral preservation**: Do the changes preserve existing behavior?
3. **Import/export consistency**: Are all imports updated? Any broken references?
4. **Type safety**: Any type errors introduced?
5. **Test coverage**: Are all changes covered by tests? Any missing test cases?
6. **Code quality**: Does the refactored code follow project conventions?
7. **Edge cases**: Any edge cases missed?
8. **Remaining work**: Anything left to do?

Provide a verdict: PASS, PASS WITH NOTES, or FAIL (with specific issues to fix).

```

Present the review to the user.
```

### Step 2: Create the refactor working directory structure

The skill should create `~/.devflow/refactor/<session-id>/` for each refactoring session, containing:

- `01-documentation.md`
- `02-plan.md`
- `03-prompts.md`
- `04-review.md`

This provides an audit trail and allows resuming interrupted refactors.

### Step 3: Update skills registry

Add to `skills/registry.json`:

```json
{
  "name": "refactor",
  "path": "devflow-plugin/commands/refactor.md",
  "description": "Multi-phase refactoring with sub-agents for documentation, planning, execution, and review",
  "category": "development"
}
```

## Acceptance Criteria

- [ ] `/devflow:refactor <file> — <description>` launches the multi-phase workflow
- [ ] Phase 1 produces a documentation report covering imports, exports, callers, callees, architecture role, and test coverage
- [ ] User reviews documentation before Phase 2 begins
- [ ] Phase 2 produces a step-by-step plan with impact analysis and risk assessment
- [ ] User reviews and approves the plan before Phase 3 begins
- [ ] Phase 3 converts the plan into standalone executable prompts
- [ ] Phase 4 executes prompts sequentially with test runs after each step
- [ ] If a step fails 3+ times, execution stops and the user is consulted
- [ ] Phase 5 produces a structured review with a pass/fail verdict
- [ ] All phase artifacts are saved to `~/.devflow/refactor/<session-id>/`
- [ ] The workflow can be interrupted and resumed (phases are independent files)
- [ ] Sub-agents receive focused context (not the entire conversation history)

## Technical Notes

- Sub-agents should be spawned using Claude Code's Task tool or equivalent subagent mechanism
- Each sub-agent gets only its required inputs — do NOT pass the full conversation context
- The `<session-id>` can be a timestamp or UUID: `$(date +%s)` or `$(uuidgen | tr '[:upper:]' '[:lower:]')`
- For large files (500+ lines), Phase 1 should focus on the public API surface, not line-by-line documentation
- Phase 4 should use the project's test command (detected from package.json scripts, Makefile, etc.)
- Consider adding a `--dry-run` flag that executes Phases 1-3 but stops before Phase 4 (useful for reviewing the plan without committing to execution)
- The prompts in Phase 3 should be self-contained enough that they could theoretically be executed in parallel (for future optimization), though sequential execution is safer
- Atomic commits during Phase 4 enable easy rollback if later steps fail: `git revert` individual steps

## Verification

```bash
# 1. Run refactor on a test file
# /devflow:refactor src/utils/helpers.ts — Split into separate utility modules

# 2. Verify Phase 1 output
cat ~/.devflow/refactor/<session-id>/01-documentation.md
# Expect: imports, exports, callers, callees, architecture role

# 3. Verify Phase 2 output
cat ~/.devflow/refactor/<session-id>/02-plan.md
# Expect: numbered steps, impact analysis, risk assessment

# 4. Verify Phase 3 output
cat ~/.devflow/refactor/<session-id>/03-prompts.md
# Expect: standalone prompts with file paths, actions, context, verification

# 5. Verify Phase 4 execution
git log --oneline -10
# Expect: atomic commits for each refactoring step

# 6. Verify Phase 5 review
cat ~/.devflow/refactor/<session-id>/04-review.md
# Expect: structured review with verdict

# 7. Verify tests pass
yarn test
# Expect: all tests pass after refactoring
```
