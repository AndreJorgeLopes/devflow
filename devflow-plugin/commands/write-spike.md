---
description: [0.11.0] Use when starting a new initiative spike, investigating technical feasibility, assessing impact across services, or writing an engineering discovery document — produces a structured spike doc with diagrams and a private notes file.
---

# Write Spike

**You are a senior staff engineer** conducting a time-boxed technical investigation. You've seen spikes that changed architectural direction and spikes that were shelved because they were too shallow. You produce spikes that make the author the domain expert — not through length, but through precision, structured gap analysis, and company-aware recommendations.

**Core principle:** A spike that doesn't classify what you know, what you can find out, and what you need others for — is just a document, not an investigation.

## Preflight (dependency check)

Before doing this skill's work, resolve dependencies from the sibling `requirements.json`:

1. Read `requirements.json` next to this SKILL.md. If absent, skip preflight (no declared deps).
2. If `devflow` is on PATH, run `devflow deps check write-spike` and use its report. Otherwise check each dep's `check` inline (`command -v` / run the command; for the named probe `hindsight`, test whether the Hindsight recall tool is reachable).
3. **Required dep missing** → STOP. Report the dep `name`, `why`, and `install` hint. Do not continue.
4. **Optional dep missing** → ask via `AskUserQuestion` (header "Optional dep"): **Provide an alternative** (path/command/endpoint) · **Continue without** (apply the dep's `degrade`) · **Abort**. In a non-interactive run (`claude --print`, cron, no TTY) default to **Continue without** — never hang.
5. Carry the chosen optional-dep behavior through the rest of the run.

## Invocation

```
/devflow:write-spike
/devflow:write-spike PROJ-123
/devflow:write-spike PROJ-123 Slack channel is C0XXXXXXX, provider docs at https://...
/devflow:write-spike We need to investigate how <new requirement> affects our <service> stack...
```

First arg = project-tracker ticket ID (optional). Everything after = free-text context.
If no ticket: free-text IS the spike scope.

## Session Check

On invocation: check context window usage. If >10%, ask: "Continue here or start fresh?" Proceed only after answer.

## Company Configuration

Resolve config (first that exists):

1. `~/.config/devflow/write-spike/company-config.yaml` — your real config. Keep it out of any repo (it is not under `~/dev`); YADM-track it.
2. `company-config.example.yaml` in this skill dir — placeholders / sensible defaults.

If neither exists, ask the user for the minimum: project tracker type, chat platform, VCS provider.

The config adapts which tools the skill uses:

```yaml
project_tracker: jira           # jira | linear | github-issues | none
project_tracker_tools: atlassian-rovo
doc_platform: confluence        # confluence | notion | google-docs | none
doc_platform_tools: atlassian-rovo
chat_platform: slack            # slack | teams | discord | none
chat_platform_tools: slack-mcp
vcs_provider: gitlab            # gitlab | github | bitbucket
memory_system: hindsight        # hindsight | none
default_spike_location: ~/docs/spikes
diagram_tool: mermaid           # mermaid | excalidraw
markdown_viewer: markdownviewer.pages.dev
```

## Process

```mermaid
flowchart TD
    A[Parse input] --> B[Phase 1: Context Assembly\nautomated, parallel]
    B --> SC{Scope check\ntoo large?}
    SC -->|"2+ moderate signals\nor 1 extreme"| DECOMP[Suggest decomposition\nuser decides]
    SC -->|"OK"| P2
    DECOMP --> P2[Phase 2: Knowledge Building\ninteractive]
    P2 --> P3[Phase 3: Document Generation\nspike doc + private notes]
    P3 --> P4[Phase 4: Validation & Learning\ngrill-me + retain]
    P4 --> OUT[Output options\ngist | confluence | local]
```

**Every phase is mandatory. Do not skip phases.**

## Phase 1: Context Assembly (automated, parallel)

Gather everything BEFORE engaging the user. Use parallel subagents:

**Agent A — Ticket & Related Issues:**
- If ticket ID: fetch via project tracker MCP tools (per config)
- Extract: spike goals, acceptance criteria, cross-team dependency table, referenced URLs
- Fetch epic/parent → get linked tickets, team contacts
- If no ticket: use free-text as scope

**Agent B — Memory & History:**
- Recall from Hindsight: domain knowledge, past initiative learnings, architecture patterns, gotchas
- Query: initiative name, affected services, related past work

**Agent C — Chat Context:**
- If channel provided: read via chat platform MCP tools (per config)
- If not: search chat platform for initiative name/ticket references
- Extract: decisions made, concerns raised, people involved, technical analysis
- If not found: ask user

**Agent D — External Documentation:**
- Extract URLs from ticket description
- Fetch using CLI tools (gh, curl) — NOT WebFetch for authenticated sources
- Provider docs (Meta, Twilio, etc.)

**Codebase Discovery:**
- Detect workspace type: single repo | parent folder with sub-repos | multi-repo worktree | external folder
- Map spike goals to affected services → find repos in workspace
- Top 20% of repos (most critical): full `devflow:codebase-walkthrough`
- Remaining 80%: light scan (grep for relevant keywords, read key files only)
- If repo not found: ask user or skip with note

### Scope Check (after Phase 1)

Flag for decomposition only when:
- **One extreme signal**: 30+ spike goals, 10+ external dependencies
- **Two moderate signals compounding**: e.g., 15 goals AND 6 external dependencies

When flagged, suggest decomposition options. User decides. If single signal slightly over (e.g., 10 goals), proceed normally.

## Phase 2: Knowledge Building (interactive)

### 2.1 Present Context Summary
For each spike goal: what we found, confidence level, source.

### 2.2 Classify Knowledge Per Goal

For each goal, classify into:

**Category A — "We know this"** (documented, verified):
→ Include in spike doc with source citation

**Category B1 — "We can find out in-session"** (code/data investigation):
→ Investigate now: grep codebase, read schemas, check git history, query chat
→ Include findings in spike doc

**Category B2 — "Real-world action required"** (external investigation):
→ Document as Nimbalist task files (ask user: global ~/docs/tasks/ or project ./tasks/)
→ Task files include: what to investigate, who, tools/access needed, expected outcome
→ Leave fields empty when unknown (e.g., `files_to_touch: []`, `estimated_effort:`)

**Category C — "Need another team"**:
→ Find team/person: check epic tickets, spike ticket deps table, chat mentions, past initiative owners
→ Contact confidence table (PRIVATE NOTES ONLY):

| Question | Team | Suggested Contact | Confidence | Source | Fallback |
|----------|------|-------------------|------------|--------|----------|

→ Questions for teams (SPIKE DOC): grouped by team, shareable format

### 2.3 Architectural Options
For significant decisions: 2-3 options with trade-offs. Reference company precedent. Flag ROI/business alignment. Ask user: "Decide now, discuss with team, or defer?"

### 2.4 Database Impact Analysis

For each schema change:
a) **Find company precedent**: search git history for migration MRs, search Hindsight, document which MR, who authored, what access needed
b) **Document company's pattern**: migration files? expand-and-contract? DBA review? what access?
c) **Zero-downtime assessment**: nullable column adds (safe), non-locking alternatives (PG11+ ADD COLUMN WITH DEFAULT, CREATE INDEX CONCURRENTLY, pg_repack, gh-ost), expand-and-contract for type changes
d) **Batching strategy**: oldest/least-used first, start batch=1000, monitor replication lag, rollback plan

### 2.5 Delegation Discussion Guide (PRIVATE NOTES ONLY)
- Which goals can be delegated? Who has relevant skills (from Jira/git history)?
- Growth opportunities per team member
- What the tech lead should own for credibility
- "Validate capacity with [manager] before assigning"

### 2.6 Investigation Backlog
Present B2 items to user. Ask if they want Nimbalist task files created (global or project folder).
Recommend: continue writing spike doc now, investigate B2 items after.

## Phase 3: Document Generation

### 3.1 Ask Save Location
"Save spike document where?
 1. Global: ~/docs/spikes/<date>-<slug>.md
 2. Project: ./docs/spikes/<date>-<slug>.md
 3. Preview only (no file yet)"

### 3.2 Generate Spike Document

Follow the spike template. Every section must be populated or explicitly marked "TBD — [reason], tracked in [task file]".

**REQUIRED REFERENCE:** Follow the template in `spike-template.md` (same directory as this skill). Every section must be populated.

All Mermaid diagrams as fenced ```mermaid blocks. Optionally generate Excalidraw versions of key diagrams (via the render-diagram skill) and include download links.

### 3.3 Generate Private Notes File

Save as `.<date>-<slug>.private.md` (dot-prefixed, same directory).

Contents:
- Delegation discussion guide (from Phase 2.5)
- Contact confidence table (from Phase 2.2)
- B2 investigation task references
- Low-confidence assumptions
- Things to discuss with manager
- Skill internal notes (what was uncertain, what needs verification)

### 3.4 Quality Gates

| Gate | Check |
|------|-------|
| Completeness | Every spike goal has an answer or explicit TBD with plan |
| Cross-team | All dependencies listed with team + contact + what we need |
| Effort | Every area has S/M/L estimate |
| Options | Significant decisions have 2-3 options with trade-offs |
| DB strategy | Migration approach documented with company precedent |
| Testing | Testing approach per layer identified |
| Diagrams | At least: architecture overview + one data flow |
| Business alignment | Phasing aligns with business timeline |
| Company patterns | Solutions follow existing patterns, not new inventions |
| Two outputs | Both spike doc and private notes generated |

## Phase 4: Validation & Learning

### 4.1 Self-Review
Placeholder scan, internal consistency, scope check, ambiguity check. Fix inline.

### 4.2 Invoke grill-me
Pass spike document to grill-me. Focus areas: dependency delays, rollback plans, independent shippability, effort estimate accuracy, single points of failure.

### 4.3 B1 Investigation Execution
If deferred from Phase 2: systematically investigate each B1 item, update spike doc with findings.

### 4.4 Retain Learning
Use `devflow:retain-learning` (or Hindsight directly) to persist: architecture decisions, cross-team contacts, gotchas, DB patterns, company patterns.

### 4.5 Output Options

"Both files ready:
 Spike doc: [path]
 Private notes: [hidden path]

 Spike doc options:
 1. Secret GitHub gist (Mermaid renders natively)
 2. Publish to Confluence (suggest locations from config)
 3. Link to ticket as comment
 4. Keep local only

 Private notes options:
 1. Keep local (default)
 2. Also create secret GitHub gist"

Default: keep local. Never auto-publish.

## Red Flags — Reconsider If You Catch Yourself

| Thought | Fix |
|---------|-----|
| "Jira ticket has everything I need" | Slack and Hindsight have insights NOT in tickets. Multi-source always. |
| "I'll skip codebase exploration" | Tickets describe intent. Code describes reality. Explore. |
| "No need for a private notes file" | Delegation + contact confidence = private. Always two files. |
| "Diagrams aren't necessary" | Spike without diagrams = wall of text. Minimum 2. |
| "grill-me is overkill" | You missed risks. You always miss risks. Run it. |
| "I'll use my default DB approach" | Check THIS company's past MRs. Follow their pattern. |
| "I'll retain learnings later" | Later = never. Persist to Hindsight in Phase 4. |
