# Review agents — definitions and activation rules

Loaded by `SKILL.md` Phase 2 in Thorough mode. Each agent receives the **context packet** (diff, MR metadata, task + epic context, document summaries, sibling MR summaries, Hindsight memories, CLAUDE.md, surrounding-code excerpts).

In Thorough mode, dispatch all active agents **in a single message with multiple Agent tool uses** so they run in parallel. Each agent returns findings as structured JSON (see "Finding format" below).

## Always-on (3) — run on every Thorough review

### Agent 1 — Bug Scanner & Error-Handling Auditor
Logic errors, null/undefined handling, race conditions, silent failures (`catch` blocks that swallow errors, unguarded property access), error propagation (does the error surface or get lost?), security (injection, unvalidated input, credential exposure). `subagent_type: general-purpose`.

### Agent 2 — Convention & CLAUDE.md Compliance
Every changed line vs CLAUDE.md rules (naming, imports, architecture, error handling, scope discipline). Flag comments that disagree with the code. Code style consistency with surrounding code. `subagent_type: general-purpose`.

### Agent 3 — Test Coverage Analyzer
Are new code paths covered by tests? Are edge cases tested (error paths, boundary values, off-by-one)? Do tests verify behaviour or just call mocks? Missing scenarios for new functionality. `subagent_type: general-purpose`.

## Conditional (3) — activate only when preconditions are met

### Agent 4 — Plan Alignment
**Activate if:** Phase 1d returned ≥1 document, OR the task has detailed acceptance criteria.
Check the implementation against documented requirements; flag deviations and scope drift. Are AC met? Is scope correct (not too narrow, not too wide)?

### Agent 5 — Git History & Blame Context
**Activate if:** any changed file has >3 distinct authors OR >10 commits in the last 6 months.
Compute via `git shortlog -sn --since=6.months <file>` and `git log --since=6.months --oneline <file> | wc -l`.
Surface historical patterns in the modified code, previous bugs in the same area, and whether the author is familiar with this code (check `git log --author=<email> -- <file>`).

### Agent 6 — Sibling MR / Epic Coherence
**Activate if:** the epic has ≥2 other MRs (merged or open).
Apply the **Aircall epic-MR investigation pattern** (from `~/.claude/CLAUDE.md`):

1. Pull every MR linked to the ticket from the Jira "Development" field (`customfield_10000`) — the highest-signal source for ticket→MR mapping.
2. Apply the **3-of-4 numbers heuristic**: an MR labelled `XYZ-NMNN` where 3 of the 4 digits match the target ticket is likely a typo by the developer. Open the MR's actual diff to confirm.
3. Compare patterns across siblings — review comments on those MRs that also apply here, integration risks, epic-level consistency.
4. Prefer ticket-ID-in-content search over title search (titles drift / get typo'd):
   - GitLab: `glab mr list --repo <project> --search "<TASK-ID>" --state all --per-page 5`
   - GitHub: `gh pr list --repo <owner/repo> --search "<TASK-ID>" --state all --limit 5`

## Finding format

Each agent must return findings as structured JSON:

```json
[{
  "agent": "bug-scanner",
  "severity": "critical|important|suggestion",
  "confidence": 85,
  "category": "bug|convention|test|alignment|history|coherence",
  "file": "src/file.ts",
  "line": 42,
  "title": "Short description",
  "detail": "Full explanation grounded in the diff and context",
  "suggestion": "Concrete fix suggestion, ideally a diff or `suggestion` block"
}]
```
