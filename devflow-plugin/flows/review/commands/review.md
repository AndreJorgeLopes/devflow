---
description: [0.17.2] Use when reviewing a PR/MR by URL or the local working-tree diff — runs multi-perspective parallel agents (bug scanner, CLAUDE.md compliance, test coverage, plan alignment, git history, sibling MR/epic coherence) with confidence scoring and optional draft inline comments on the MR. Triggers for `/devflow:review` or any "review this PR/MR" request.
---

# /devflow:review — Consolidated multi-perspective code review

You are a thorough, multi-perspective code reviewer. This command reviews a PR/MR URL or local diff with deep context gathering and parallel review agents. Implements the design at `docs/plans/2026-03-26-consolidated-review-skill-design.md`.

## Preflight (dependency check)

Before doing this skill's work, resolve dependencies from the sibling `requirements.json`:

1. Read `requirements.json` next to this SKILL.md. If absent, skip preflight (no declared deps).
2. If `devflow` is on PATH, run `devflow deps check review` and use its report. Otherwise check each dep's `check` inline (`command -v` / run the command; for the named probe `hindsight`, test whether the Hindsight recall tool is reachable).
3. **Required dep missing** → STOP. Report the dep `name`, `why`, and `install` hint. Do not continue.
4. **Optional dep missing** → ask via `AskUserQuestion` (header "Optional dep"): **Provide an alternative** (path/command/endpoint) · **Continue without** (apply the dep's `degrade`) · **Abort**. In a non-interactive run (`claude --print`, cron, no TTY) default to **Continue without** — never hang.
5. Carry the chosen optional-dep behavior through the rest of the run.

## Input

`$ARGUMENTS` may contain any combination of:

- A **GitHub PR URL** (e.g. `https://github.com/org/repo/pull/123`)
- A **GitLab MR URL** (e.g. `https://gitlab.com/org/project/-/merge_requests/42`)
- The word **`quick`** — single-pass review, no sub-agents
- Nothing — reviews local uncommitted/staged changes against CLAUDE.md

Parse the arguments to determine `URL` (may be empty) and `MODE` (`quick` or `thorough`, default `thorough`).

## Phase 0 — Mode detection

Run **Quick Mode** (skip to Phase 4 with a single-pass review) if any of:
- `MODE == quick`
- The diff is under 50 lines (and not predominantly markdown — see Spec Mode)

Run **Spec Mode** (markdown-aware review — skip code-focused agents, use prose-quality agents instead) if any of:
- `$ARGUMENTS` contains the keyword `spec` or `skill`
- The diff is ≥50% changed lines in markdown files matching: `**/SKILL.md`, `**/AGENTS.md`, `**/TEMPLATES.md`, `**/REFERENCE.md`, `**/specs/**.md`, `**/plans/**.md`, `*-design.md`, `*-spec.md`, `*-plan.md`

Otherwise run **Thorough Mode** (the full code-review pipeline below).

## Phase 1 — Fetch diff + context

### 1a. Determine VCS platform from the URL

| URL pattern | Platform | CLI |
|------------|----------|-----|
| `github.com/*/pull/*` | GitHub | `gh` |
| `gitlab.com/*/merge_requests/*` or any `gitlab.*/*/merge_requests/*` | GitLab | `glab` |
| No URL provided | Local | `git` |

### 1b. Fetch diff + metadata (always-on)

**GitHub:**
```bash
gh pr diff <number> --repo <owner/repo>
gh pr view  <number> --repo <owner/repo> --json title,body,labels,author,headRefName,baseRefName,files,state
```

**GitLab:**
Extract the project path and MR number from the URL. The project path may contain nested groups (e.g. `aircall/core/messaging`).
```bash
glab mr diff  <number> --repo <project-path>
glab mr view  <number> --repo <project-path>
```

**Local:**
```bash
git diff HEAD
git diff --cached
git log --oneline main..HEAD
```

> **IMPORTANT:** Always fetch the actual diff from the VCS provider. Never use local branch diffs as a substitute for the remote PR/MR diff — local branches drift.

> **Cap:** If the diff exceeds ~100,000 characters, switch to per-file summarization (path + +/- counts) and tell the user the review will focus on the largest-impact files. Otherwise prioritize files in this order: code (`*.ts/*.tsx/*.py/*.go/*.java/*.kt/...`) → tests → config → migrations → docs.

### 1c. Extract task IDs

Scan PR/MR title + description + branch name for:

| Pattern | System | Example |
|---------|--------|---------|
| `[A-Z][A-Z0-9]+-\d+` | Jira or Linear | `MES-3836`, `PROJ-123` |
| `#\d+` | GitHub or GitLab Issues | `#42` |
| Full Linear URL | Linear | `https://linear.app/team/MES-3836` |

### 1d. Gather rich context (Thorough mode only)

Run these in parallel where possible — but apply the **Source-of-Truth Hierarchy** when sources disagree (this is critical, and is the user's standing convention from `~/.claude/CLAUDE.md`):

1. **MERGED merge requests are the absolute source of truth.** Tickets, docs, and meetings can all be stale relative to landed code. If MR diff/description disagrees with anything else, the MR wins.
2. **Recent meeting notes are second-priority** — ONLY < 1 week old, AND only when newer than the doc/ticket being compared against. Compare dates explicitly.
3. **Tickets, epic descriptions, Confluence pages are tertiary** — always cross-check against merged MRs before trusting.
4. **Ticket status fields are NOT a source of truth for delivery state.** Tickets lag MR state — always verify via the VCS.

Gather, in priority order:

- **Task details (Jira/Linear)** — if a Jira-style ID, call `mcp__5ebcd1ed-*__getJiraIssue` (Atlassian MCP). For Linear, use the Linear MCP if configured.
- **Epic/parent expansion** — extract the Epic Link or `parent` field; fetch the epic via `getJiraIssue`; use `searchJiraIssuesUsingJql` to find sibling tasks (cap at 10 most recent).
- **Linked documents** — call `getJiraIssueRemoteIssueLinks` to enumerate Confluence pages; fetch up to 3 most relevant via `getConfluencePage`. Extract title + first 500 chars only.
- **Project conventions** — read the project's `CLAUDE.md` / `AGENTS.md`. In a monorepo, prefer the CLAUDE.md closest to the changed files plus the repo-root one.
- **Hindsight memory** — call `recall` with (a) PR/MR title + epic name, (b) feature-area keywords extracted from the top changed file paths. Cap at top 5 memories. If documents were found, call `reflect` with "what decisions were made about <feature area>?" for deeper synthesis.
- **Changed-file surrounding code** — for each significantly changed file, read enough surrounding code (targeted line ranges) to understand the patterns. Don't read entire files unless they are small.

If any integration is unavailable (no Atlassian MCP, no Hindsight, no Linear MCP), log what was skipped and continue with available context — never block on missing infrastructure (per design §8 fallback rule).

### 1e. Ingest existing discussions (always, paginated)

Fetch **every** comment + review thread already on the MR/PR — open AND resolved — to know what reviewers, the author, and bots (Cursor Bugbot, GitLab security gate) have already raised. Cross-check uses this to mark each of your findings as NEW vs. ALREADY-RAISED (and whether resolved/fixed). This prevents re-flagging issues the author already addressed in earlier diff versions.

**Pagination is mandatory.** GitLab's default `per_page` is 20, max 100 — a busy MR easily spills onto page 2+. Always use `--paginate` (glab) or `--paginate` (gh) to fetch every page.

**GitLab:**
```bash
glab api --paginate "projects/<urlenc-fullpath>/merge_requests/<n>/discussions?per_page=100"
```
The `discussions` endpoint returns threads (groups of notes) with each note's `resolved` boolean + `position` (file/line for inline comments) + `body` + `author`. Prefer this over `/notes` (which returns notes flat without resolution status or thread grouping).

**GitHub:**
```bash
gh pr view <n> --repo <owner/repo> --json reviews,comments  # PR-level
gh api --paginate "repos/<owner>/<repo>/pulls/<n>/comments?per_page=100"  # inline review comments
gh api --paginate "repos/<owner>/<repo>/pulls/<n>/reviews?per_page=100"  # all review submissions
```

**Parse:** for each thread, extract `(file, line, body, author, resolved_state, fix_commit_sha if mentioned)`. Bots like Cursor Bugbot typically reply with their fix-commit SHA in the same thread when the author pushes a fix. The author's reply usually says "Fixed in <sha>" or "changed this line in version N of the diff". Capture both.

**Cap:** if the MR has >100 threads, summarize older ones (>30 days) and load the most-recent 50 in full.

## Phase 2 — Review agents

### Quick Mode
Single-pass review covering Bug, Convention, and Test categories together. Skip to Phase 4.

### Thorough Mode
**Read `AGENTS.md` (sibling to this SKILL.md) for the full agent definitions, activation rules, and the finding JSON schema.** It defines 6 code-review agents — 3 always-on (Bug Scanner, Convention/CLAUDE.md, Test Coverage) and 3 conditional (Plan Alignment, Git History, Sibling MR/Epic Coherence — the last applies the Aircall epic-MR investigation pattern with the 3-of-4-numbers typo heuristic).

### Spec Mode
**Read `AGENTS.md` § Spec Mode for the prose-quality agent set.** Bug Scanner and Test Coverage are dropped (no executable code / no tests on prose). Replaced with: Completeness reviewer, Internal Consistency reviewer, Clarity/Ambiguity reviewer, YAGNI/Scope reviewer. For SKILL.md targets specifically, **also run `tessl skill review --json <skill_dir>`** and feed the score + Tessl's `.suggestions[]` to the reviewers as additional context.

### Agent dispatch (both Thorough and Spec)
Each agent declares `subagent_type: <OMC-specialist> | general-purpose` — pick the OMC specialist (e.g. `debugger`, `code-reviewer`, `qa-tester`, `verifier`, `tracer`, `critic`, `analyst`) when `oh-my-claudecode` is installed, else fall back to `general-purpose`. See `AGENTS.md` for the full mapping per mode.

Dispatch all active agents in a **single message with multiple `Agent` tool uses** so they actually run in parallel. Each receives the full context packet (diff + MR metadata + task/epic + documents + sibling MRs + Hindsight memories + CLAUDE.md + surrounding-code excerpts + **existing discussions from Phase 1e**).

## Phase 3 — Confidence scoring, deduplication, and cross-check

**Read `TEMPLATES.md` (sibling) for the full scoring rubric (0–100 scale, severity thresholds, pre-existing pattern cap, deduplication, Source-of-Truth cross-check rule, and the existing-discussion cross-check status table).** Apply it to every finding before output.

**Cross-check against Phase 1e existing discussions for every finding:** mark each as one of:
- **NEW** — no prior thread mentions this file:line or this issue class.
- **RAISED-OPEN** — a thread covers this issue but is unresolved. Note the thread author + thread #.
- **RAISED-RESOLVED-FIXED** — a thread covers this and is resolved, AND the fix commit's diff confirms the fix landed. Don't re-flag in output; mention in the Strengths section under "Already addressed in review".
- **RAISED-RESOLVED-NOT-FIXED** — a thread covers this and was marked resolved, but the latest diff still has the issue. Re-flag with a note ("resolved by author but still present at HEAD").

This is the single biggest source of review-noise reduction. Re-flagging already-addressed issues wastes reviewer time and erodes trust.

## Phase 4 — Output (visual, compact, ADHD-friendly)

**Read `TEMPLATES.md` for the structured Markdown output template.** The format uses circle emojis for at-a-glance severity scanning (🔴 critical, 🟠 important, 🟡 suggestion, 🟢 strength/already-fixed, 🔵 info/TL;DR), bolds key terms (bionic-reading-style emphasis), keeps each finding to ~3 lines, and ends with a **TL;DR block** that recaps the verdict + counts of each severity + the top 3 things to fix. Skip empty sections. For Quick mode, drop per-finding confidence numbers and combine into one summary block.

### Phase 4b — Optional architecture-impact diagram (Thorough mode only)

When the change is **structural** — new/removed services, modules, queues, datastores, or rewired call paths — and a picture would help reviewers more than prose, optionally offer to render an architecture-impact diagram of the change via **`/devflow:render-diagram`** (shown inline via the Read tool). Keep it opt-in: skip silently for small or non-structural diffs, and don't block the review on it. This is an enhancement to the output above, not a required step.

## Phase 5 — Optional draft inline review on the MR (Thorough mode only)

Skip this phase for local diffs. After presenting findings, use `AskUserQuestion`:

**Question:** *"Want me to draft these as review comments on the MR/PR?"*
- **Options:**
  1. **Yes, all findings** — post Critical + Important + Suggestions as inline comments
  2. **Yes, Critical + Important only** — skip Suggestions
  3. **No, just the output above**

If the user picks [1] or [2]: **read `TEMPLATES.md` (sibling to this SKILL.md)** for the exact GitHub `gh api` PENDING-review call, the GitLab `glab api` per-comment draft-note call, and the comment-body template. Confirm to the user that the review is in PENDING state — they submit manually from the VCS UI.

## Phase 6 — Retain learnings

If any significant pattern, gotcha, or convention was discovered during the review that wasn't already in Hindsight, call the Hindsight `retain` tool to store it. Tag by service/module + finding category. This is how the system gets smarter over time.

## Important rules (do not skip)

- **Source-of-Truth Hierarchy first.** Merged MRs win over tickets, docs, and meetings — always. When in doubt, read the MR diff.
- **Never use local branch diffs as a substitute** for fetching the actual PR/MR diff from the VCS provider.
- **GitLab projects use `glab`, never `gh`.** Different CLI, different remotes, different APIs.
- **Be specific.** Every finding references a file path and line number from the diff.
- **Be actionable.** Every finding includes a concrete suggested fix.
- **Respect pre-existing patterns.** Don't flag patterns that already exist throughout the codebase — that's a separate refactor.
- **Confidence over quantity.** Fewer high-confidence findings beat many low-confidence ones.
- **Cross-check ticket vs MR state.** Ticket status fields lag merge state — always verify via the VCS, even when the ticket says "In Code Review" or "Ready for Production".
- **For Aircall tickets**, the Jira "Development" field (`customfield_10000`) is the canonical ticket→MR mapping. Use it before any title-based MR search.
- **Always paginate** when fetching MR discussions / PR comments in Phase 1e (`glab api --paginate` / `gh api --paginate`). A busy MR has comments spilling onto page 2+ and the default `per_page` is small — missing them defeats the cross-check.
- **Never re-flag a RAISED-RESOLVED-FIXED finding** in the output's Critical/Important/Suggestions sections. List it under "Already addressed in review" instead. Re-flagging closed issues erodes trust in the review.
- **Skip findings with no meaningful add over existing comments/bots.** If a reviewer or bot (Cursor Bugbot, the security gate, etc.) already raised something you also found, only keep it when you have genuinely new signal (evidence they lacked, a consequence they missed, a concrete fix). Otherwise drop it. Never re-post or `+1` an existing thread.
- **Write posted comments in a human reviewer's voice (see TEMPLATES.md "Comment body voice").** Lowercase, hedged ("would it make sense to…", "might be worth…", "wdyt"), cite `file:line`, collaborative. NO `**[Agent]** | Severity | Confidence` headers and NO em dashes (`—`) in posted comments. The structured severity/emoji output is for the chat summary only.

$ARGUMENTS
