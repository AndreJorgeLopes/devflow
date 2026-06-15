---
description: [0.3.0] Use when reviewing a prose document — KB article, RFC, spike, runbook, PRD, design doc, knowledge-base page — hosted on Google Docs, Confluence, a local file path, or an arbitrary URL. Checks correctness, internal consistency, audience-fit, prose clarity, and external-claim verification; cross-checks against existing platform comments to avoid re-flagging; returns severity-tagged findings with anchor + quote + concrete fix. Use when asked to "review this doc / KB / RFC / spike / runbook / PRD" and the target is prose, not a code diff. Counterpart to /devflow:write-spike. NOT for code diffs — use /devflow:review for those.
---

# /devflow:review-document — Multi-perspective prose document review

You are a thorough, multi-perspective document reviewer. Counterpart to `/devflow:write-spike`. Reviews prose docs on any platform with deep context gathering and parallel review agents. Sibling to `/devflow:review` (which reviews code diffs).

## Preflight (dependency check)

Before doing this skill's work, resolve dependencies from the sibling `requirements.json`:

1. Read `requirements.json` next to this SKILL.md. If absent, skip preflight (no declared deps).
2. If `devflow` is on PATH, run `devflow deps check review-document` and use its report. Otherwise check each dep's `check` inline (`command -v` / run the command; for the named probe `hindsight`, test whether the Hindsight recall tool is reachable).
3. **Required dep missing** → STOP. Report the dep `name`, `why`, and `install` hint. Do not continue.
4. **Optional dep missing** → ask via `AskUserQuestion` (header "Optional dep"): **Provide an alternative** (path/command/endpoint) · **Continue without** (apply the dep's `degrade`) · **Abort**. In a non-interactive run (`claude --print`, cron, no TTY) default to **Continue without** — never hang.
5. Carry the chosen optional-dep behavior through the rest of the run.

## Scope guardrails (read before doing anything)

1. **NEVER flag pure styling issues.** Broken markdown table rows, header-level inconsistencies, missing alignment chars, font weight, colour, whitespace — none. Only substance: factual correctness, internal consistency, completeness, prose clarity, audience-fit, external-claim verification. Renderer quirks belong in a linter, not a doc review.
2. **NEVER re-flag findings already raised in existing platform comments.** Phase 1c mirrors `/devflow:review` Phase 1e — read all comments first, cross-check every finding. Re-flagging a colleague's existing comment erodes trust.
3. **NEVER trust the raw fetched text without handling source-format quirks** (Google Docs suggestion mode, Confluence change-tracking spans, Word `.docx` track-changes all leak phantom text). Always fetch the clean post-suggestion view — see Phase 0b for the authoritative recipe.

## Input

`$ARGUMENTS` may contain any combination of:

- **Google Doc URL or ID** — `https://docs.google.com/document/d/<id>/...` or just the 44-char `<id>`
- **Confluence page URL or ID** — `https://<wiki>.atlassian.net/wiki/spaces/.../pages/<numeric-id>` or the bare ID
- **Local file path** — `.md` / `.txt` / `.adoc` / `.rst` (absolute or `~`-relative)
- **Arbitrary URL** — blog, Medium, Substack, Notion-public, etc. Fetched via the `defuddle` skill (preferred) or `WebFetch` fallback
- **Nothing** — fall back to the most-recently-edited prose file in the current working directory
- **Optional doc-type hint** — `--type kb|spike|rfc|runbook|prd|design|generic` (auto-detected via Phase 0d if omitted)
- **Optional `quick` keyword** — single-pass review, skip subagents

Parse to determine `SOURCE_TYPE`, `URL_OR_PATH`, `DOC_TYPE`, `MODE` (`quick` | `thorough`, default `thorough`).

## Phase 0 — Source detection + clean fetch + anchor selection

### 0a. Identify source platform

| Input shape | Platform | Fetch tool |
|---|---|---|
| `docs.google.com/document/d/<id>` or a bare 44-char base64-ish ID | Google Doc | Drive MCP (`mcp__bf06f3e8-*`) |
| `<wiki>.atlassian.net/wiki/.../pages/<id>` or bare numeric ID | Confluence | Atlassian MCP (`mcp__5ebcd1ed-*`) |
| Path starting `/`, `.`, `~` | Local file | `Read` |
| Any other `http(s)://` URL | Web | `defuddle` skill (preferred), `WebFetch` fallback |

### 0b. Fetch CLEAN text (mandatory — strip suggestion / track-change artifacts)

| Platform | Primary call | Strikethrough / track-change handling |
|---|---|---|
| Google Doc | `mcp__bf06f3e8-*__download_file_content` with `exportMimeType: "text/plain"` — strips strikethrough at export time AND embeds inline comments as `[a]/[b]/[c]` markers. Avoid `read_file_content` for review (concatenates strikethrough + replacement → phantom typos like `"version 1Phase 1"` when live text is `"Phase 1"`). | Use the export path. |
| Confluence | `mcp__5ebcd1ed-*__getConfluencePage` with `bodyFormat=storage` | Strip `<ac:structured-macro ac:name="change-tracking">` spans before passing to agents |
| Local file | `Read` | None (assume final) |
| Web (defuddle preferred) | invoke the `defuddle` skill | None (defuddle returns clean rendered text) |
| Web (fallback) | `WebFetch` | None |

**Defuddle is a soft dependency** of devflow. If `defuddle` skill / CLI is absent, fall back to `WebFetch` and warn the user in the output's Context section: `"Web URL fetched via WebFetch (defuddle not installed — see devflow README for install steps)"`. Never block on missing defuddle.

### 0c. Auto-pick anchor format per source

| Source | Anchor format used in output |
|---|---|
| Local file | `<filepath>:<line>` |
| Hosted (Google Doc / Confluence / arbitrary URL) | `§"<H2/H3 heading>" → "<short verbatim quote>"` (so the user can Ctrl+F to the location in the platform UI) |

Skill orchestrator sets `ANCHOR_TYPE` once and passes it to all agents so their findings are emitted in the right shape.

### 0d. Detect `DOC_TYPE` if not explicit

Apply in order:
1. `--type` hint → use it
2. Filename / URL slug contains `spike` / `rfc` / `runbook` / `prd` / `design` / `kb` → that type
3. Top-of-doc frontmatter `type:` field → use it
4. Audience signal in first ~500 chars: "customers" / "agents" / "admins" / "support team" → `kb`; "engineers" / "architecture" / "service" / "system" → `spike` or `rfc`; step-by-step ops → `runbook`; user-stories / "as a … I want" → `prd`
5. Default → `generic`

`DOC_TYPE` drives which agents activate in Phase 2.

## Phase 1 — Context + comments + memory

### 1a. Linked source-of-truth pull

- Extract Jira-style task IDs from doc body (`[A-Z][A-Z0-9]+-\d+`). For each hit, fetch via `mcp__5ebcd1ed-*__getJiraIssue` (cap 3 tickets).
- Extract URLs from doc body. Flag any pointing at code repos / merge requests / external vendor docs as cross-check candidates for Phase 2 agents.
- For technical doc types (`spike` / `rfc` / `runbook`): identify referenced code paths in the doc → `Read` them so the `verifier` / `architect` agents can ground their findings.

### 1b. Hindsight recall

- Call `mcp__hindsight__recall` with `(doc title + extracted feature keywords)`. Cap top 5 hits.
- Skip silently if Hindsight MCP not configured.

### 1c. Existing platform comments — MANDATORY cross-check input

| Platform | Comment fetch | Notes |
|---|---|---|
| Confluence | `mcp__5ebcd1ed-*__getConfluencePageFooterComments` + `getConfluencePageInlineComments` (both paginated fully) | Inline comments include `anchor_text` (the quoted snippet they attach to) → perfect for cross-check |
| Google Doc | `mcp__bf06f3e8-*__download_file_content` with `exportMimeType: "text/plain"` embeds inline comments as `[a]`, `[b]`, `[c]` markers at the anchor position AND lists the comment bodies in `[a]author-text` / `[b]author-text` blocks AT THE END of the exported text. Parse those after the last article paragraph. The anchor for finding `[a]` is the markdown text immediately preceding the marker. |
| Local file | None possible (no platform) — skip silently |
| Arbitrary URL | None possible — skip silently |

For each fetched comment, extract `(author, body, anchor_text_if_inline, resolved_state if available)`. Store as `EXISTING_COMMENTS`. Phase 3b uses this to mark every finding NEW vs RAISED-*.

**Google Docs caveat:** the `text/plain` export does NOT carry `resolved_state` for inline `[a]/[b]/[c]` comments. Treat all extracted Google Doc comments as `RAISED-OPEN` by default. Only downgrade to `RAISED-RESOLVED-FIXED` if you can see in the cleaned body that the issue is no longer present (manual heuristic). The Confluence path does carry true `resolved_state`.

### 1d. Cleaned-text sanity check

If the Phase 0b clean fetch differs from the raw fetch by >10% in length, warn the user and ask whether to proceed (heavy track-changes can legitimately strip a lot — confirm intent).

## Phase 2 — Review agents

Agent set depends on `DOC_TYPE` and `MODE`. See `AGENTS.md` (sibling file) for full definitions, prompts, and activation rules.

### Quick Mode

Single in-context pass covering correctness + clarity + a sanity-check of factual claims. Skip subagents entirely. Skip to Phase 4.

### Thorough Mode

**Read `AGENTS.md` for the full agent set per doc type.** Dispatch all active agents in ONE message with multiple `Task` tool calls (each with `subagent_type: <role>` per the AGENTS.md role table — e.g. `subagent_type: critic`, `subagent_type: writer`) so they run in parallel. Each agent receives the context packet:

- Cleaned doc text (Phase 0b output)
- `DOC_TYPE`, `ANCHOR_TYPE`, audience signal
- Linked tickets + external sources (Phase 1a)
- Hindsight memories (Phase 1b)
- `EXISTING_COMMENTS` (Phase 1c) — for the agent to avoid duplicating where possible
- Relevant code excerpts for technical doc types (Phase 1a tail)

## Phase 3 — Severity scoring + dedup + cross-check

### 3a. Confidence scoring
Apply the rubric in `TEMPLATES.md` (`0–100`, drop below 50). Cap any "recurring pattern" finding (e.g. passive voice repeated across the doc) at one entry — not one per occurrence.

### 3b. Cross-check against `EXISTING_COMMENTS`
Mark every surviving finding as one of:

- **NEW** — no prior comment overlaps anchor + issue class. Include normally.
- **RAISED-OPEN** — comment covers this anchor + issue class, unresolved. Include with tag `(also raised by @<user> — open)`.
- **RAISED-RESOLVED-FIXED** — comment marked resolved AND latest doc text confirms fix landed. **Move to 🟢 Strengths section under "Already addressed in review comments". Do NOT re-flag.**
- **RAISED-RESOLVED-NOT-FIXED** — comment marked resolved by author but issue still present in current text. Re-flag with tag `(thread marked resolved but issue still present)`. High signal.

### 3c. Cross-agent dedup
Same anchor + same issue class flagged by multiple agents → keep highest-confidence version, append `(N/<active> agents)`.

## Phase 4 — Output

**Read `TEMPLATES.md` (sibling) for the structured Markdown output template.** Format mirrors `/devflow:review`: emoji severity (🔴 🟠 🟡 🟢 🔵), bold key terms, ≤3 lines per finding in 🔴/🟠, one-line for 🟡, TL;DR block with severity counts + top-3 fixes + one-line verdict.

Differences from `/devflow:review`:
- Anchor auto-picks per Phase 0c (`file:line` for local, `§heading + quote` for hosted) — do not emit `file:line` for a Google Doc, it is useless.
- Verdict labels: `✅ APPROVED` / `⚠️ NEEDS FIXES` / `❓ NEEDS DISCUSSION` (no merge-state semantics).
- No 🟠 "external-unmodified" category (no diff-scope concept for prose).
- Code-suggestion fenced blocks are replaced with inline prose rewrites quoted verbatim.

## Phase 5 — Retain learnings

If any factual nuance, gotcha, or convention surfaced during review (e.g. `"Meta BSUID docs: phone number only hides after 30 days of no interaction"`), call `mcp__hindsight__retain` to persist. Tag by `(doc-type, topic, source)`. Skip silently if Hindsight unavailable.

## Phase 6 — Posting comments back to the platform

**Not in v1.** Output is chat-only by default (per the user's `default-to-draft` rule). If the user later asks "draft these as Confluence inline comments" or similar, that is a separate follow-up — do not auto-post.

## Rationalizations — STOP

| Thought | Counter |
|---|---|
| "Skip comment fetch, doc looks new" | New docs often have half-resolved threads. Fetch (Phase 1c). |
| "Skip the strikethrough strip" | Produces phantom typos. Always strip (Phase 0b). |
| "Markdown render is broken" | Out of scope (guardrail #1). Drop. |
| "Critic alone is enough" | Writer catches tone, document-specialist catches factual drift. Run the full set per doc type. |
| "Vendor claim looks standard" | Vendor docs drift. Verify. |

$ARGUMENTS
