---
description: [0.24.3] Lock the full test inventory before any implementation code is written. Reads spec+plan+AC, writes ALL failing tests in a batch, emits a Test Inventory doc, and gates with user approval.
---

> **Attribution:** Base TDD workflow vendored and adapted from [haletothewood/behavioural-tdd v1.8](https://tessl.io/registry/haletothewood/behavioural-tdd), Apache-2.0. Modifications: Phase 1 widened from single-test to batch; added Phase 0 (read artefacts) and Phase 1.7 (Test Inventory) and Phase 1.8 (user-approval gate); Phases 2-3 delegated to `/devflow:executing-plans` (the devflow wrapper that delegates to upstream `superpowers:executing-plans` for the per-task red/green/refactor loop AND forces the post-implementation handoff to `/devflow:finish-feature`).

You are at the test-locking phase of devflow's new-feature pipeline. Your job is to write the full failing-test inventory from the locked spec + plan + AC, then gate on user approval before any production code is written.

## Step 0 — Re-establish the feature worktree (do this before Phase 0)

This phase is normally reached via `devflow:phase-handoff`, which forks a FRESH throwaway worktree that is NOT on the feature branch (`spawn_task` always forks off the default branch; there is no way to pin it). Move to the real feature worktree first, using the `devflow handoff context` block in the message that invoked this skill.

1. Parse from that block: `Feature worktree`, `Feature branch`, `Main repo (shared .git)`. If no such block is present (skill invoked manually, not via a handoff), skip Step 0 — you are already in the right place.

2. Ensure the feature worktree exists on the feature branch, then make it your working directory:
   ```bash
   feature_wt="<Feature worktree>"
   feature_branch="<Feature branch>"
   main_repo="<Main repo>"

   git -C "$main_repo" worktree prune   # clear stale registrations (a worktree dir deleted with rm -rf)
   # Validity check, not mere existence: recreate unless we can cd in AND are already on the feature branch.
   # (`[ -d ]` alone would skip recovery for a stale non-worktree dir or a detached/wrong-branch checkout.)
   if ! ( cd "$feature_wt" 2>/dev/null && [ "$(git branch --show-current 2>/dev/null)" = "$feature_branch" ] ); then
     git -C "$main_repo" worktree add "$feature_wt" "$feature_branch" 2>/dev/null || {
       # path occupied, or branch already checked out elsewhere — reuse that existing checkout.
       # Strip the leading `worktree ` token (not awk $2) so worktree paths containing spaces survive.
       existing="$(git -C "$main_repo" worktree list --porcelain | awk -v b="refs/heads/$feature_branch" '
         /^worktree /{ $1=""; sub(/^ /,""); w=$0 } /^branch /{ if ($2==b) print w }')"
       [ -n "$existing" ] && feature_wt="$existing"
     }
   fi
   cd "$feature_wt"

   on="$(git branch --show-current)"
   [ "$on" = "$feature_branch" ] || { echo "WORKTREE RECOVERY FAILED: in '$on', expected '$feature_branch' at $feature_wt"; exit 1; }
   ```

3. Every later step — Phase 0's artefact reads, writing the test files + Test Inventory, `git` commits, the terminal `phase-handoff` — runs in `$feature_wt`. The Read/Edit tools need an ABSOLUTE path: open each artefact as `$feature_wt/<relative-path-from-the-block>`. If the worktree could not be recreated, read any committed artefact with `git -C "$main_repo" show "$feature_branch:<rel-path>"`. Never write into the throwaway spawn worktree — it is an orphan the user prunes separately.

## Phase 0 — Read artefacts

1. **Detect ticket + branch:**
   ```bash
   branch="$(git branch --show-current)"
   # Sanitize branch name into a filesystem-safe slug.
   # Replaces forward-slashes (from feat/X, fix/X conventions) with hyphens.
   branch_slug="$(echo "$branch" | tr '/' '-')"
   ```
   Extract ticket ID from `$branch` (regex `[A-Z]+-[0-9]+`); if none, use `none`.

2. **Mark chapter:**
   Call `mark_chapter` with `{title: "Lock Tests — <TICKET>", summary: "Writing failing test inventory"}`.

   If `mark_chapter` is unavailable (e.g. running outside Claude Code), skip silently.

3. **Set terminal window title (CLI Claude Code only — silent no-op in Claude Desktop):**
   ```bash
   [ -t 1 ] && printf '\e]2;%s — Lock Tests\007' "<TICKET>" || true
   ```
   In Claude Desktop there is no controlling terminal — the visible phase signal comes from `mark_chapter` (step 2).

4. **Read the frozen-state file** from the previous phase:
   `.devflow/state/${branch_slug}/plan.md`
   Treat its "Source-of-truth artefacts" list as the only authoritative inputs. (phase-handoff commits this file to the branch, so it is present after Step 0. If it is somehow missing, fall back to the `devflow handoff context` block from the invoking message — that block carries the same artefact paths + locked decisions — or `git -C "$main_repo" show "$feature_branch:.devflow/state/${branch_slug}/plan.md"`.)

5. **Locate inputs from the frozen-state file.** The frozen-state file's "Source-of-truth artefacts" section lists the exact paths to:
   - Spec (e.g. `docs/specs/my-feature.md`)
   - Plan (e.g. `docs/plans/2026-05-19-my-feature-plan.md`)
   - Test inventory if past lock-tests (e.g. `docs/specs/my-feature-test-inventory.md`)

   Read those exact paths — do NOT use a hardcoded `docs/specs/<feature>.md` template. The frozen-state file is the single source of truth for input locations.

   AC extraction: read the spec file's `## Acceptance Criteria` section if present. If absent, fall back to extracting behavioral assertions from `## Edge Cases` + `## Testing Strategy` + `## Implementation Plan` (which the spec template guarantees). Warn the user if the spec has no explicit AC section.

6. **Light-weight escape hatch:** estimate feature size from the plan. If the plan file is < 100 lines OR has ≤ 3 numbered tasks, AND the spec has no new AC, ask via `AskUserQuestion`:
   - Question: "This looks like a trivial change. Skip the lock-tests gate?"
   - Options: "No — keep the gate (Recommended)" / "Yes — skip"
   - Default focus: "No — keep the gate".
   - If user skips: invoke `devflow:phase-handoff --phase lock-tests --next-phase impl --no-handoff`. Then print:

   ```
   Trivial change — lock-tests gate skipped. Context is already small; no new session needed for the implementation phase. Invoke `/devflow:executing-plans` here (devflow's wrapper around the upstream executing-plans skill; the wrapper forces the post-implementation handoff to go to `/devflow:finish-feature` instead of the upstream's `finishing-a-development-branch`).
   ```

   Then exit.

7. **Check git status:**
   ```bash
   git status --porcelain
   ```
   If not clean, warn: "Uncommitted changes detected. Lock-tests works best on a clean tree." Prompt via `AskUserQuestion`:
   - Question: "Continue with dirty tree?"
   - Options: "Yes — continue" / "No — stash and retry"

## Phase 1 — RED (batch)

Constraints carried from haletothewood:

| Rule | Why |
|---|---|
| Public interface only | Tests survive internal rewrites |
| One requirement per test | Fast feedback, clear failure signal |
| No mocking private methods | Avoids coupling tests to implementation |
| No assertions on internal state | Preserves behavioral integrity |
| Shameless Green allowed in Phase 2 | Establishes feedback loop before optimizing |

Mock at **system boundaries only** — external APIs, databases, time, file system. Never mock your own classes, internal collaborators, or anything you control. Use dependency injection to make boundaries explicit and mockable.

For UI components, query by the highest-level user-facing role (`getByRole('button', { name: /submit/i })` over `getByTestId`).

**Steps:**

1. **Detect test framework** from project: look for `jest.config.*`, `vitest.config.*`, `pytest.ini`, `spec/spec_helper.rb`, etc. Match existing patterns.

2. **For each acceptance criterion**, write ONE failing test that:
   - Calls only the public interface
   - Asserts one specific output, return value, rendered element, or observable state change
   - Will fail with a CLEAR assertion error (not a compile/import error preferred, but module-not-found is acceptable for genuinely new code)

3. **Surface edge cases** the spec doesn't explicitly call out but that good judgment demands (boundary values, error cases, concurrency where relevant). For each edge case you ADD, also add a row to the Coverage map in Phase 1.7. For each candidate edge case you CONSIDERED but rejected, add a bullet to the `## Considered but not added` section with the reason for rejection.

4. **Place tests** in the canonical test directory for the framework (e.g. `__tests__/`, `spec/`, `tests/`, `*.test.ts` siblings). Follow existing project conventions.

## Phase 1.5 — Verify each test fails for the RIGHT reason

```bash
# Run the new tests (framework-specific)
# Examples:
#   jest path/to/new.test.ts
#   vitest run path/to/new.test.ts
#   pytest tests/test_new.py -v
#   bundle exec rspec spec/path/spec.rb
```

Each test MUST fail with:
- "X is not defined" / "Cannot find module" (acceptable for new code)
- OR an assertion mismatch (preferred — proves the test setup is wired)

NOT acceptable: syntax errors, fixture-loading errors, framework-misconfig errors. If you see those, fix them before proceeding.

## Phase 1.7 — Emit Test Inventory doc

Write `docs/specs/<feature>-test-inventory.md`:

```markdown
# Test Inventory: <feature>

**Generated:** <ISO-8601 timestamp>
**Ticket:** <TICKET-ID>
**Spec:** docs/specs/<feature>.md
**Plan:** docs/plans/<feature>-plan.md

## Coverage map (AC → test)

| AC | Test file | Test name | Status |
|---|---|---|---|
| AC1: <text> | path/to/file.test.ts | "<test name>" | RED |
| AC2: <text> | path/to/file.test.ts | "<test name>" | RED |
| ... | ... | ... | ... |

## Considered but not added

- **<case description>** — rationale (e.g. "out of scope per spec non-goals §X", "already covered by existing test at <path>", "deferred to follow-up ticket TICKET-Y")
- **<case description>** — rationale
- ...

## Framework
<detected framework + version + config file path>

## Verification command
```bash
<exact command to run only these tests>
```
```

## Phase 1.8 — User approval gate

Use `AskUserQuestion` with:
- Question: "Test inventory written to `docs/specs/<feature>-test-inventory.md`. N tests added, K considered-but-skipped. Approve and proceed to implementation?"
- Options:
  - "Approve & proceed (Recommended)" — proceeds to handoff
  - "Add more tests" — loops back to Phase 1 with the user's additions
  - "Discuss" — opens free-form Q&A; user re-invokes when ready

**Do NOT proceed to implementation without explicit approval.**

## Phase 2 — GREEN (delegated)

After approval, invoke `devflow:phase-handoff --phase lock-tests --next-phase impl`. The handoff skill commits the artefact docs to the branch, gates on a one-click `AskUserQuestion`, then spawns a new Claude Desktop session via `mcp__ccd_session__spawn_task` titled `[<TICKET>] [MR#<N>] Implementation` (visible in the sidebar). The spawned session starts cold in a fresh throwaway worktree; its initial prompt leads with the slash-command invocation `/devflow:executing-plans` (devflow's wrapper around the upstream executing-plans skill — guarantees the post-implementation handoff goes to `/devflow:finish-feature`) and embeds the self-contained `devflow handoff context` block (feature branch/worktree + relative artefact paths + worktree-recovery commands) that the wrapper's Step 0 consumes to re-establish the feature worktree before driving per-task red/green against the tests locked in this phase.

## Phase 3 — REFACTOR (delegated)

Handled per-task inside `/devflow:executing-plans` (the devflow wrapper, which delegates to the upstream executing-plans flow), not centrally.

## Important

- Read frozen-state file FIRST. Treat its artefacts list as the only inputs.
- Never write production code in this skill — only test code.
- Every test in Phase 1 must fail before exiting Phase 1.5.
- Phase 1.8 gate is mandatory unless the trivial-feature escape hatch (Phase 0 step 6) was taken.

$ARGUMENTS
