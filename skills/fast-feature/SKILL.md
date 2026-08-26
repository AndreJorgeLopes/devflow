---
name: fast-feature
description: Use when driving a single already-specced ticket through devflow in one session, unattended, resolving ambiguity from the codebase rather than by asking, then spec, plan, and lock-tests back-to-back with an independent reviewer standing in for the human gate, spawning a new session only for the execute phase. Also the per-ticket driver that orchestrate-epic invokes.
---

You are a senior engineer who moves a well-defined ticket from "assigned" to "tests locked, ready to implement" in a single focused session, then hands ONLY the implementation off to a fresh session. You do not re-litigate a ticket that already has clear acceptance criteria, and you do not fragment context across a session per phase.

**Core principle:** the standard devflow pipeline spawns a new session at every phase boundary (spec → plan → lock-tests → impl = three spawns). For a ticket that is already specced, that is friction. `fast-feature` collapses `resolve ambiguity → spec → plan → lock-tests` into ONE session and spawns exactly once, at the execute boundary, so implementation starts cold and clean while all the planning stays in one warm context.

**It runs unattended.** Every human gate in the standard pipeline is replaced by an automated equivalent: ambiguity is resolved from the codebase and recorded rather than asked about, and the test-inventory approval is given by an independent reviewer subagent rather than by a person. The one thing that still stops the run is a fork only a human can settle, which is reported as a blocker instead of guessed at.

## When to Use

- A single ticket whose acceptance criteria are already written and unambiguous (typical for a refined Jira ticket).
- You want to reach a locked test inventory fast, then start implementation in its own session.
- `orchestrate-epic` calls this per workable ticket, passing a distilled context brief.

Do NOT use for: greenfield features that genuinely need design exploration (use `/devflow:new-feature` → full brainstorming), or multi-ticket coordination (use `/devflow:orchestrate-epic`).

## Inputs (`$ARGUMENTS`)

- **Ticket** — a Jira URL or key (e.g. `MES-4459`), or a branch already named for one. Required. If absent, ask.
- **Context brief** (optional) — a block of pre-distilled context (from `orchestrate-epic`, or pasted by the user): locked decisions, links to a PRD/design/spec, cross-repo notes, security/AC constraints. **Treat a provided brief as TRUSTED. Do NOT re-discover a dimension the brief already covers** (per-dimension trust). Only fill gaps the brief leaves open.

## Core pattern

```mermaid
flowchart TD
    A[Step 0: establish feature worktree for the ticket] --> B[Step 1: load context<br/>recall + trust the provided brief]
    B --> C{Step 2: ACs ambiguous?}
    C -->|yes, settleable from code| D[Decide and record<br/>in the spec decision log]
    C -->|yes, needs a human| J[STOP, report the blocker]
    C -->|no| E[Proceed]
    D --> F[Step 3: spec-feature<br/>SKIP its terminal handoff]
    E --> F
    F --> G[Step 4: writing-plans<br/>SKIP its terminal handoff]
    G --> H[Step 5: lock-tests<br/>independent reviewer replaces the approval gate]
    H --> I[Step 6: THE ONE SPAWN<br/>phase-handoff lock-tests to impl, --unattended]
```

## Step 0 — Establish the feature worktree for this ticket

You may be launched cold (spawned by `orchestrate-epic` into a throwaway worktree off the default branch) or run manually from within a repo. Either way, END this step in a feature worktree named for the ticket.

1. Parse the ticket key (regex `[A-Z]+-[0-9]+`) from `$ARGUMENTS` or the current branch.
2. **If you are already in a feature worktree for THIS ticket** (`git branch --show-current` contains the key and is not the default branch), skip to Step 1.
3. Otherwise resolve the repo and create the worktree:
   - Invoke `/devflow:resolve-repo` with the ticket to detect the VCS platform, match the ticket to its repo, and clone if missing. (When called by `orchestrate-epic`, the brief already names the repo — trust it, skip re-detection.)
   - Create the feature worktree under the standard location and switch to it:
     ```bash
     repo_root="<resolved main clone, e.g. ~/dev/aircall/messaging>"
     repo_name="$(basename "$repo_root")"
     slug="<short-kebab-summary>"                      # e.g. tag-taxonomy-crud
     branch="feat/<TICKET>/${slug}"
     wt="$HOME/dev/.worktrees/${repo_name}/$(echo "$branch" | tr '/' '-')"
     git -C "$repo_root" worktree add "$wt" -b "$branch" 2>/dev/null \
       || git -C "$repo_root" worktree add "$wt" "$branch"   # branch already exists
     cd "$wt"
     ```
   - Confirm: `git branch --show-current` == `$branch`. If not, STOP and report — do not spec on the wrong branch.

## Step 1 — Load context

1. **Recall** from Hindsight: `"<project>: <TICKET>"`, `"<project>: <domain from branch>"`, `"<project>: architecture"`. If Hindsight is unavailable, say so and continue.
2. **Read the context brief** if one was provided. For every dimension it covers (PRD, design, cross-repo impact, locked decisions, security/AC constraints), treat it as authoritative and do NOT re-fetch or re-derive it. Only research dimensions the brief leaves open.
3. **Read the ticket** itself (via `acli`/Atlassian) for its acceptance criteria and scope, unless the brief already reproduces them verbatim.

## Step 2 — Resolve ambiguity without stopping

Judge whether the acceptance criteria leave a REAL, decision-changing ambiguity (a fork where two reasonable engineers would build different things).

- **No real ambiguity → skip brainstorming entirely.** State one line: "ACs are unambiguous; skipping brainstorm." Go to Step 3.
- **Real ambiguity → resolve it without stopping.** Do NOT invoke `/devflow:brainstorming`, which is an interactive loop. Instead: state each fork explicitly, pick the option most consistent with the surrounding code and the ticket's own acceptance criteria, and record the choice plus its rationale in the spec's decision log so a reviewer can overturn it in one comment. If a fork is genuinely unresolvable from the repo (it needs a product decision, another team's answer, or access you do not have), do NOT guess: stop, report the fork, and leave the ticket unstarted.

Never invent ambiguity to justify a detour. Never guess past a fork that needs someone else's answer.

**The line to hold:** ambiguity that the codebase can settle, you settle. Ambiguity that only a human can settle is a blocker, not a question to ask mid-run.

## Step 3 — Spec (in this session)

Invoke `/devflow:spec-feature` with the ticket + resolved context. Let it write `docs/specs/<feature>.md` and extract tasks.

**OVERRIDE its terminal handoff.** `spec-feature`'s last step invokes `devflow:phase-handoff --phase spec --next-phase plan`, which would spawn a new session. In `fast-feature` you do NOT want that spawn. When `spec-feature` reaches that step, **skip the `phase-handoff` call** (equivalently, invoke it with `--no-handoff`, which makes it a no-op that returns control) and continue directly to Step 4 in THIS session. The spec doc on disk is the input to the plan phase — the intermediate frozen-state file and artefact commit are not needed until the execute spawn (Step 6) produces them.

## Step 4 — Plan (in this session)

Invoke `/devflow:writing-plans`. Its Step 0 (re-establish worktree) is a no-op here — no handoff-context block is present and you are already in the feature worktree. Let it write the plan doc.

**OVERRIDE its terminal handoff** the same way: `writing-plans` ends by invoking `devflow:phase-handoff --phase plan --next-phase lock-tests`. Skip that spawn (or pass `--no-handoff`) and continue directly to Step 5. The plan doc on disk is the input to lock-tests.

## Step 5 — Lock tests (in this session)

Invoke `/devflow:lock-tests`. Its Step 0 is a no-op (already in the feature worktree). Since the spec and plan were produced in THIS session, feed it their known paths directly if it cannot find a frozen-state file (its Phase 0 documents that fallback). Run it through:

- Phase 1 (write the batch of failing tests), Phase 1.5 (verify each fails for the right reason), Phase 1.7 (Test Inventory doc).

**Phase 1.8's user-approval gate is replaced, not skipped.** Dispatch an independent reviewer subagent that did not write the tests, give it the ticket, the spec, the plan and the Test Inventory, and have it answer: does every acceptance criterion have a test, does every test fail for the right reason today, is any test tautological (would it pass before the change), and does anything exceed the ticket's scope. Approve on its verdict, not your own.

**Never self-approve in the same context.** The gate's purpose is a second pair of eyes; a human was only ever one way to get that. If the reviewer returns NEEDS_WORK, fix and re-dispatch. If it returns NEEDS_WORK twice on the same point, stop and report rather than looping.

If the trivial-change escape hatch fires (tiny plan, no new AC), follow lock-tests' own escape path (it hands off with `--no-handoff` and tells you to run `/devflow:executing-plans` here) — that is the one case where execute also stays in-session.

## Step 6 — The one spawn: hand off execute

This is the ONLY phase boundary that spawns a new session. After the reviewer approves, invoke:

```
devflow:phase-handoff --phase lock-tests --next-phase impl
```

Run it WITHOUT `--no-handoff`, and WITH `--unattended` so it does not gate on an `AskUserQuestion`. It commits the spec/plan/test-inventory docs to the branch (durability) and spawns the `[<TICKET>] [MR#<N>] Implementation` session whose prompt leads with `/devflow:executing-plans`. That new session does the red/green/refactor against the locked tests and finishes via `/devflow:finish-feature`.

If the runtime cannot spawn a session without a human click, do not wait on one: continue into `/devflow:executing-plans` in THIS session and say plainly in the final report that execute did not get a cold context.

Then exit. Report: spec + plan + test-inventory produced in this session, and the implementation session spawned.

## Common Mistakes

- **Letting an intermediate phase spawn a session.** Steps 3 and 4 MUST suppress their `phase-handoff` — otherwise you get the very 3-spawn fragmentation this skill exists to avoid.
- **Stopping to ask when the codebase already answers it.** Decide, record the decision and its rationale, and let review overturn it.
- **Re-discovering what the brief already gave you.** A provided brief is trusted input, not a starting hint.
- **Speccing on the wrong branch.** Step 0 must end on `feat/<TICKET>/...`, never the default branch.

## Red flags — STOP if you think:

| Thought | Reality |
|---|---|
| "I'll let spec-feature hand off normally, it's simpler" | That spawns a plan session and breaks the single-session contract. Suppress it. |
| "The ACs are clear but I'll ask anyway to be safe" | Asking is the thing this skill exists to avoid. Decide and record it. |
| "I'll approve the test inventory myself, it looks fine" | The gate is a second pair of eyes. Dispatch the reviewer. |
| "This fork is unclear, I'll pick something and move on" | Only if the codebase settles it. If it needs a product or another team's answer, stop and report. |
| "The brief mentions the PRD, let me go read the whole PRD" | Per-dimension trust: the brief IS the PRD context for this run. Do not re-fetch. |
| "Let me start implementing here since I'm warm" | Execute gets its own cold session (except the trivial-escape path). Spawn at Step 6. |

## Important

- `spec-feature` → `writing-plans` → `lock-tests` all run in ONE session here; only Step 6 spawns.
- Never write production code in this skill — it stops at a locked, reviewer-approved test inventory, then hands off.
- Always end Step 0 on the ticket's feature branch. If worktree creation fails, STOP.
- The test-inventory gate is not optional, but it is satisfied by an independent reviewer rather than by a human. Never satisfy it yourself.

$ARGUMENTS
