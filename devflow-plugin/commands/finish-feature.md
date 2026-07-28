---
description: [0.24.2] Finish a feature — run verification, an adversarial review gate (re-grounded on the original design doc + ticket ACs, not the plan) and a deferral-closure gate, then create the PR, retain learnings, and hand off cleanup to the terminal.
---

You are finishing a feature. Run the full completion pipeline before handing off to the developer for worktree cleanup.

**IMPORTANT:** Do NOT clean up the worktree or switch branches from inside this session — that is a terminal action performed by the developer after the session ends.

## Preamble (first action)

1. Detect ticket ID deterministically (D1): `TICKET=$(extract_ticket_id "$(git branch --show-current)") || TICKET=none` (lib abstains → `none`).
2. Call `mark_chapter` with `{title: "Finish — <TICKET>", summary: "Finishing the feature"}`.
   If `mark_chapter` is unavailable (e.g. running outside Claude Code), skip silently.
3. Set terminal window title (CLI Claude Code only — silent no-op in Claude Desktop):
   ```bash
   [ -t 1 ] && printf '\e]2;%s — Finish\007' "<TICKET>" || true
   ```
   In Claude Desktop there is no controlling terminal — the visible phase signal comes from `mark_chapter` (step 2).

## Determinism (offload to the shared lib; AI only on abstain)

Source the determinism-fix lib once before your bash work:

```bash
for f in ~/.claude/lib/determinism/functions/*.sh; do . "$f"; done
```

The functions are **sound, not complete** (`~/.claude/lib/determinism/CONTRACT.md`): exit
`0` = confident value, `10` = abstain → AI, `1` = error → AI. Deterministic-first; the
model only runs on a non-zero exit. Used here: `extract_ticket_id`, `is_protected_branch`,
`count_commits`. The commit message + PR body TEXT stay model-authored (creative) — only
their FORMAT is pinned (Steps 6 & 7).

## Steps

1. **Assess the current state.** Run:

   ```bash
   git branch --show-current
   git status
   git diff --stat
   git log --oneline main..HEAD 2>/dev/null || git log --oneline master..HEAD
   ```

   **Branch guard (D2 — deterministic, hard stop).** Do not "confirm by eye"; run the lib predicate:

   ```bash
   BRANCH=$(git branch --show-current)
   if is_protected_branch "$BRANCH"; then echo "BLOCKED: on protected branch '$BRANCH' — refusing to finish"; exit 1; fi
   ```

   Then confirm there are changes to finalize.

2. **Run verification checks.** Execute the full check pipeline:

    ```bash
    devflow check
    ```

    Also confirm the generated flow mini-plugins are in sync with their canonical skills (a skill edit that forgot `make flows` must not ship a drifted flow):

   ```bash
   make flows-check
   ```

   If `devflow check` is not available, run lint, types, and tests directly:

   ```bash
   yarn lint
   yarn build
   yarn test --changedSince=main
   ```

   **If checks fail**, report the failures clearly and stop. Do NOT continue past this step with failing checks. Help the user fix issues if they ask.

3. **Diff self-test (Surgical Changes).** Run `git diff origin/main...HEAD` and scan for:

   - Changes unrelated to the feature (formatting, adjacent refactors, comment cleanup).
   - Dead-code removals beyond orphans YOUR changes created.
   - "Improvements" made in passing.

   If any exist, surface them to the user. Offer to move them to a separate PR or revert. Don't silently ship them.

4. **Source-grounded review gate (the adversarial guardrail).**

   > **Why this step exists.** Passing the locked tests is necessary but not sufficient. Across this pipeline the requirements get compressed into a spec + plan, and every downstream phase is handed that compression as its "only authoritative input" — so any requirement the plan silently dropped, and any correctness/robustness issue the spec never spelled out, sails through to here unseen. The implementations that beat ours on the same spec earned their edge from an adversarial review loop (a human reviewer, a review bot) that this autonomous pipeline otherwise has no equivalent of. This gate adds that missing pass — and it re-grounds on the ORIGINAL sources, not the plan.

   a. **Identify the ORIGINAL authoritative sources — NOT the plan.**
      - The external design / spec / RFC / spike document the feature was built from. Try the deterministic path first (D3): `grep -roEh '[^ ]+\.(md|pdf|txt)' .devflow/state/"$BRANCH"/*.md 2>/dev/null | sort -u`. If that yields exactly one artefact, use it; if zero or several, THEN scan the frozen-state "Source-of-truth artefacts", the ticket's linked docs, or ask the user (the model only judges when the grep is ambiguous).
      - The implementation ticket's acceptance criteria: fetch the ticket (branch ticket ID) via the Atlassian/Jira MCP — read its ACs AND its "Development" field. Ticket-level requirements (tests required, ops/CI wiring, observability, meta-deliverables) routinely live OUTSIDE the design doc.
      - Do **not** use the generated plan or spec-artifact as the alignment target. The plan is a lossy compression of these sources; aligning against it reproduces whatever it dropped.
      - If you can locate neither the original design doc **nor** the ticket ACs, **STOP and ask the user** for them. Never fall back to the plan/spec-artifact as the alignment target — a review with no original-source target is not this gate, and proceeding silently re-opens the dropped-requirement hole this step exists to close.

   b. **Capture the COMPLETE feature delta, then review it.** Stage everything first so committed, uncommitted, AND untracked changes are all in scope, and diff against the merge-base — `git diff HEAD` is empty once executing-plans has committed, and `/devflow:review`'s local mode only ever sees the working tree:
      ```bash
      git add -A
      BASE="$(git merge-base origin/main HEAD)"
      git diff --cached "$BASE" --stat   # scope sanity-check (see "Fail loud" below)
      git diff --cached "$BASE"          # the exact diff handed to the reviewers
      ```
      Dispatch two subagents **in a single message** (parallel) against THAT diff:
      - **Alignment** (`verifier`) — does the diff satisfy EVERY requirement in the original design doc and EVERY ticket AC? Walk the design doc's *detail* sections (Design, Resilience, edge-case discussion, inline code blocks/comments) — not just its summary or "migration / MR-N" checklist. Behavioral requirements buried in discussion are precisely the ones earlier phases drop while still capturing the headline deliverables. List each requirement unmet or only partially met, with its source citation.
      - **Bug / robustness** (`debugger`) — correctness, error handling, resilience, and how the *real* runtime dependencies behave (endpoint/payload shapes, failure modes, concurrency, idempotency). Surface issues a careful reviewer would raise even when the spec is silent on them.
      - Do **not** use `/devflow:review` for this gate: pre-PR its local mode reviews only the working tree (empty once the work is committed) and it takes no diff-range argument, so it silently reviews nothing. `/devflow:review` is the right tool *after* Step 7, by PR URL. Either way this is a fresh review pass; never self-attest that the work is aligned.
      - **Fail loud:** if `git diff --cached "$BASE" --stat` is empty or much smaller than the feature, you are reviewing the wrong range — a clean review of an empty diff is NOT a pass. Fix the range before continuing.

   c. **Gate on the findings.** Present them as a pinned table (D4), not a free-text blob —
      `| Finding | Severity | Source |` (Severity ∈ Critical/Important/Suggestion), no prose
      preamble like "I found the following issues". Then gate by severity. Every Critical/Important alignment-gap or bug must be **fixed**, or **explicitly accepted by the user** (via `AskUserQuestion`, with the reason and any follow-up ticket recorded) before continuing. Do not open the PR with unresolved Critical/Important findings. For every alignment-gap you **fix** here, add or extend a test that locks the recovered requirement — the locked suite was generated from the same compressed sources and does not yet cover it, so the fix would otherwise ship with zero regression protection.

5. **Deferral closure gate.** Enumerate every conscious deferral and open item from this build:
   - STOP-and-ask / blocked points raised during implementation (e.g. an integration the agent could not wire without a human-supplied secret or decision).
   - "deferred / follow-up / out of scope (for now)" notes in the plan, frozen-state files, or commit messages.
   - `TODO` / `FIXME` introduced in this feature's diff.

   Deferrals raised only verbally during implementation do **not** survive into this session (implementation ran in a separate spawned session). Treat "nothing recorded" as suspicious, not as "none": also `recall` from Hindsight for this branch/feature, and run the deferral grep deterministically (D5 — run it, do not narrate from memory): `git diff "$(git merge-base origin/main HEAD)"..HEAD | grep -E '^\+.*(TODO|FIXME)'`. If anything was deferred but is written down nowhere, you cannot close this gate — ask the user.

   For each, it must be either (a) done now, (b) **explicitly accepted by the user** as a tracked follow-up (record where it is tracked), or (c) pulled into this MR. A deliberate decision to defer is fine; a deferral that ships unnoticed is the failure mode this gate exists to catch — it is how a correctly-identified-but-blocked deliverable (CI wiring, an ops hook, an alert) ends up missing from the MR with nobody realising.

6. **Stage and commit.** If there are uncommitted changes:
   - Stage relevant changes: `git add -A`
   - Analyze the full diff to generate a commit message (text is yours to author; FORMAT is pinned, D6):
     - Subject line MUST match `^(feat|fix|refactor|chore|test|docs)(\([^)]+\))?: .{1,72}$` (conventional commits, subject ≤72 chars).
     - Be concise (1-2 lines).
     - Reference the ticket ID (`$TICKET`) if not `none`.
   - Present the commit message to the user for approval before committing.

7. **Push and create PR.** Push the branch and create a pull request:

   ```bash
   git push -u origin HEAD
   ```

   Then create the PR using `gh`:

   ```bash
   gh pr create --title "<title>" --body "<body>"
   ```

   The PR body MUST use these exact section headings, in this order (D7 — pinned format):
   - `## Summary` — 2-3 bullet points of changes
   - `## Ticket` — ticket reference (or "none")
   - `## Testing` — what was verified

   Present the PR URL to the user.

8. **Retain session learnings.** Review the session and retain important discoveries:
   - Architecture decisions made during this feature
   - Gotchas or non-obvious patterns encountered
   - Bug root causes and fixes
   - Use Hindsight `retain` for each learning, tagged with the project name

9. **Present the summary and hand off cleanup.** Compute the counts deterministically
   (D8 — do not narrate from memory):

   ```bash
   COMMITS=$(count_commits "origin/main..HEAD") || COMMITS=$(git rev-list --count origin/main..HEAD)
   FILES=$(git diff --stat origin/main..HEAD | tail -1 | grep -oE '[0-9]+ file' | grep -oE '[0-9]+')
   ```

   Emit the block with those exact integers (no fences inside it):

   ```
   ## Feature Complete

   **Branch:** <branch-name>
   **PR:** <pr-url>
   **Commits:** <COMMITS>
   **Files changed:** <FILES>

   ### Checks
   - [PASS/FAIL] Lint
   - [PASS/FAIL] Types
   - [PASS/FAIL] Tests

   ### Learnings Retained
   - [list of retained memories]

   ### Cleanup (run from your terminal)
   To remove the worktree after PR is merged:
     devflow done <branch-name>
     # or manually:
     wt drop <branch-name>
   ```

## Important

- Never merge to `main` from inside the agent — use PRs.
- Never clean up the worktree from inside the agent — that's a terminal action.
- If checks fail, stop and help fix. Do not skip verification.
- **The Step 4 review gate aligns against the ORIGINAL design doc + ticket ACs, never the generated plan** — the plan is a lossy compression; aligning to it reproduces its omissions.
- **The review gate is a guardrail, not a guarantee.** It raises the odds of catching alignment gaps and robustness bugs the spec was silent on; it does not replace careful implementation. Run it as a real, fresh review pass — never self-attest.
- **A deferred requirement may ship only if the user explicitly accepted it.** A correct decision to defer is fine; a deferral that ships unnoticed is not.
- Always retain learnings before ending the session.

$ARGUMENTS
