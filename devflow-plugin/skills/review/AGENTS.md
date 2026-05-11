# Review agents — definitions and activation rules

Loaded by `SKILL.md` Phase 2 in Thorough mode. Each agent receives the **context packet** (diff, MR metadata, task + epic context, document summaries, sibling MR summaries, Hindsight memories, CLAUDE.md, surrounding-code excerpts).

In Thorough mode, dispatch all active agents **in a single message with multiple Agent tool uses** so they run in parallel. Each agent returns findings as structured JSON (see "Finding format" below).

## Subagent selection — prefer OMC specialists when available

If `oh-my-claudecode` (OMC) is installed (detect via `omc --version` succeeding, OR the presence of `/oh-my-claudecode:*` slash commands in the session), use the specialized OMC agent for each role below — it's purpose-built and typically produces sharper findings than a generic-purpose subagent. Each agent's spec lists `subagent_type: <OMC> | general-purpose` — pick the OMC one if available, else fall back to `general-purpose`.

| Agent role | OMC specialist | Generic fallback |
|---|---|---|
| Bug Scanner | `debugger` | `general-purpose` |
| Convention compliance | `code-reviewer` | `general-purpose` |
| Test coverage | `qa-tester` | `general-purpose` |
| Plan alignment | `verifier` | `general-purpose` |
| Git history | `tracer` | `general-purpose` |
| Sibling MR coherence | `critic` | `general-purpose` |

The fallback is genuinely a fallback — never block the review on OMC's absence. Findings from `general-purpose` are still high quality; they're just less role-specialized.

## Always-on (3) — run on every Thorough review

### Agent 1 — Bug Scanner & Error-Handling Auditor
Logic errors, null/undefined handling, race conditions, silent failures (`catch` blocks that swallow errors, unguarded property access), error propagation (does the error surface or get lost?), security (injection, unvalidated input, credential exposure). `subagent_type: debugger | general-purpose`.

### Agent 2 — Convention & CLAUDE.md Compliance
Every changed line vs CLAUDE.md rules (naming, imports, architecture, error handling, scope discipline). Flag comments that disagree with the code. Code style consistency with surrounding code. `subagent_type: code-reviewer | general-purpose`.

### Agent 3 — Test Coverage Analyzer
Are new code paths covered by tests? Are edge cases tested (error paths, boundary values, off-by-one)? Do tests verify behaviour or just call mocks? Missing scenarios for new functionality. `subagent_type: qa-tester | general-purpose`.

## Conditional (3) — activate only when preconditions are met

### Agent 4 — Plan Alignment
**Activate if:** Phase 1d returned ≥1 document, OR the task has detailed acceptance criteria.
Check the implementation against documented requirements; flag deviations and scope drift. Are AC met? Is scope correct (not too narrow, not too wide)? `subagent_type: verifier | general-purpose`.

### Agent 5 — Git History & Blame Context
**Activate if:** any changed file has >3 distinct authors OR >10 commits in the last 6 months.
Compute via `git shortlog -sn --since=6.months <file>` and `git log --since=6.months --oneline <file> | wc -l`.
Surface historical patterns in the modified code, previous bugs in the same area, and whether the author is familiar with this code (check `git log --author=<email> -- <file>`). `subagent_type: tracer | general-purpose`.

### Agent 6 — Sibling MR / Epic Coherence
**Activate if:** the epic has ≥2 other MRs (merged or open).
Apply the **Aircall epic-MR investigation pattern** (from `~/.claude/CLAUDE.md`):

1. Pull every MR linked to the ticket from the Jira "Development" field (`customfield_10000`) — the highest-signal source for ticket→MR mapping.
2. Apply the **3-of-4 numbers heuristic**: an MR labelled `XYZ-NMNN` where 3 of the 4 digits match the target ticket is likely a typo by the developer. Open the MR's actual diff to confirm.
3. Compare patterns across siblings — review comments on those MRs that also apply here, integration risks, epic-level consistency.
4. Prefer ticket-ID-in-content search over title search (titles drift / get typo'd):
   - GitLab: `glab mr list --repo <project> --search "<TASK-ID>" --state all --per-page 5`
   - GitHub: `gh pr list --repo <owner/repo> --search "<TASK-ID>" --state all --limit 5`

`subagent_type: critic | general-purpose`.

## Spec Mode agents (markdown-prose review)

Activated by SKILL.md Phase 0 when the diff is dominated by markdown spec/skill files (or `$ARGUMENTS` contains `spec`/`skill`). Bug Scanner + Test Coverage are dropped. The replacement set:

| Spec-mode agent | OMC specialist | Generic fallback | Focus |
|---|---|---|---|
| Completeness | `verifier` | `general-purpose` | Placeholders, TBD, TODO, incomplete sections, missing edge cases |
| Internal consistency | `code-reviewer` | `general-purpose` | Contradictions, terminology drift, conflicting requirements |
| Clarity / ambiguity | `critic` | `general-purpose` | Vague phrases, multi-interpretation language, undefined terms |
| YAGNI / scope | `analyst` | `general-purpose` | Unrequested features, over-engineering, scope creep relative to the stated intent |
| **For SKILL.md targets:** frontmatter + structural quality check | (deterministic — not an agent) | n/a | Run `tessl skill review --json <skill_dir>` and surface the score + `.suggestions[]` to the other 4 agents as additional context |

Convention/CLAUDE.md compliance + Plan Alignment + Sibling MR coherence (the conditional ones from Thorough Mode) remain available in Spec Mode when their preconditions are met. Git History only activates if the markdown files themselves have >3 authors / >10 commits — usually not the case for new specs.

## Finding format

Each agent must return findings as structured JSON. **`scope` is mandatory** so the output can mark findings the user cannot leave as inline MR comments (because the underlying issue is in a file the MR doesn't change).

```json
[{
  "agent": "bug-scanner",
  "severity": "critical|important|suggestion",
  "confidence": 85,
  "category": "bug|convention|test|alignment|history|coherence|completeness|consistency|clarity|yagni",
  "scope": "in-diff|in-related-changed-file|external-unmodified",
  "file": "src/file.ts",
  "line": 42,
  "title": "Short description",
  "detail": "Full explanation grounded in the diff and context",
  "suggestion": "Concrete fix suggestion, ideally a diff or `suggestion` block",
  "external_anchor_file": "src/types/country.ts (the file whose contents motivate this finding when scope=external-unmodified)"
}]
```

**`scope` semantics:**
- `in-diff` — the file:line is in this MR's diff. Can be posted as an inline review comment.
- `in-related-changed-file` — file IS in the diff but the specific line cited is OUTSIDE any hunk (uncommon; happens when the agent cites a line in a file that's only partially changed). Usually convert to nearest in-diff line; otherwise treat like `external-unmodified`.
- `external-unmodified` — the underlying issue lives in a file/line NOT changed by this MR. **The output MUST mark this with 📄 in the finding title** and a note like "_(external file — cannot post as inline review comment on this MR; consider opening a separate ticket or refactor)_". Phase 5 (draft inline review) MUST skip these findings (GitHub/GitLab require inline comments on changed lines).

When `scope=external-unmodified`, populate `external_anchor_file` so the user knows where the underlying issue actually lives, even though the finding was triggered by something in the diff. Example from MR !2146: a `country` empty-string risk where `country` is read in the diff but the `Country` type defining `'' | CountryCode` lives in an unmodified `domain/.../country.ts` — finding's `file` would be the diff site, `scope=external-unmodified`, `external_anchor_file` points at the type definition.
