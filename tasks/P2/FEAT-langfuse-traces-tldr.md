---
id: FEAT-langfuse-traces-tldr
title: "Langfuse Traces TLDR Skill"
priority: P2
category: features
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - devflow-plugin/commands/traces-summary.md
  - skills/registry.json
---

# Langfuse Traces TLDR Skill

## Context

Langfuse collects traces from all agent sessions — every tool call, every LLM invocation, every MCP interaction is logged. However, this data sits in a dashboard that requires manual exploration. Users don't have a quick way to understand what the traces are telling them: which skills are slow, which tools fail often, where tokens are being wasted, and what patterns emerge across sessions.

## Problem Statement

1. **Raw data, no insights**: Langfuse captures everything but users must manually browse the dashboard to find patterns
2. **No trend detection**: Users can't see at a glance whether error rates are increasing, which skills are most used, or where token spend is concentrated
3. **No optimization suggestions**: The data contains signals for improvement (e.g., "you do X manually every session" or "MCP Y has a 30% failure rate") but these are never surfaced
4. **Context switching**: Checking traces requires leaving the terminal and opening a browser — breaking flow

## Desired Outcome

- A `/devflow:traces-summary` command that queries Langfuse and produces an actionable TLDR report
- The report covers: session counts, durations, tool usage, error rates, token consumption, and patterns
- Concrete optimization recommendations are generated from the data
- The entire report is viewable in the terminal without switching to a browser

## Implementation Guide

### Step 1: Create the `/devflow:traces-summary` skill command

Create `devflow-plugin/commands/traces-summary.md`:

````markdown
---
name: traces-summary
description: Query Langfuse traces and produce an actionable insights report
---

# Langfuse Traces TLDR

## Step 1: Query Langfuse API

Fetch recent traces from the Langfuse API:

```bash
# Fetch traces from the last 7 days (default)
LANGFUSE_HOST="${LANGFUSE_HOST:-http://localhost:3100}"
SINCE=$(date -v-7d +%Y-%m-%dT00:00:00Z 2>/dev/null || date -d '7 days ago' +%Y-%m-%dT00:00:00Z)

# Get traces
curl -s "${LANGFUSE_HOST}/api/public/traces?fromTimestamp=${SINCE}&limit=100" \
  -H "Authorization: Bearer ${LANGFUSE_PUBLIC_KEY}" \
  | jq '.'

# Get sessions
curl -s "${LANGFUSE_HOST}/api/public/sessions?fromTimestamp=${SINCE}&limit=100" \
  -H "Authorization: Bearer ${LANGFUSE_PUBLIC_KEY}" \
  | jq '.'

# Get observations (tool calls, LLM invocations)
curl -s "${LANGFUSE_HOST}/api/public/observations?fromTimestamp=${SINCE}&limit=500" \
  -H "Authorization: Bearer ${LANGFUSE_PUBLIC_KEY}" \
  | jq '.'
```
````

If Langfuse is not reachable or credentials are missing, report the error and suggest running `devflow up` or configuring Langfuse keys.

## Step 2: Analyze the Data

From the fetched traces and observations, compute:

### Session Metrics

- Total sessions in the period
- Average session duration (from first to last trace event)
- Longest session and what it was doing
- Sessions per day (trend: increasing, stable, decreasing?)

### Tool Usage

- Most frequently used tools (top 10)
- Average duration per tool
- Slowest tools (P95 latency)
- Tool error rates (failed / total calls)

### Token Consumption

- Total input tokens, output tokens
- Average tokens per session
- Most token-expensive sessions (which tasks consume the most?)
- Token efficiency: output tokens / input tokens ratio

### Skill/Command Usage

- Most invoked skills/commands
- Skills that are never used (candidates for removal or improvement)

### Error Analysis

- Tools with highest error rates
- Most common error messages
- Error trends (getting worse or better?)

### MCP Performance

- MCP server response times
- MCP call failure rates
- Specific MCP tools that are slow or unreliable

## Step 3: Generate Recommendations

Based on the analysis, generate actionable recommendations:

- **Skill creation opportunity**: "You perform <action> manually in N sessions — consider creating a skill for it"
- **Reliability issue**: "MCP <server> fails N% of the time — investigate health"
- **Performance issue**: "<tool> averages Xs response time — consider caching or optimization"
- **Token waste**: "Sessions averaging >Xk tokens for <task-type> — consider compaction or better scoping"
- **Unused infrastructure**: "Skill <X> hasn't been used in N days — consider deprecating"

## Step 4: Format the Report

Output the report in this format:

```
## Session Insights (last 7 days)

| Metric         | Value          |
|----------------|----------------|
| Sessions       | 42             |
| Avg duration   | 23min          |
| Total tokens   | 1.2M (in: 980k, out: 220k) |
| Error rate     | 3.2%           |

### Most Used Tools
1. Read (342x) — avg 0.1s
2. Bash (218x) — avg 1.8s
3. Edit (156x) — avg 0.2s
4. hindsight_recall (89x) — avg 3.2s ⚠️ slow
5. hindsight_retain (34x) — avg 1.1s

### Most Used Skills
1. /devflow:new-feature (18x)
2. /devflow:create-pr (12x)
3. /devflow:refactor (4x)

### Error Hotspots
- Bash: 12 failures (5.5%) — mostly permission errors
- hindsight_retain: 4 timeouts (11.8%) ⚠️
- devflow check: 5 failures — review check rules

### Recommendations
1. 🔧 Create a skill for "database migration" — you do it manually in 8 sessions
2. ⚠️ hindsight_retain fails with timeout 12% — check Hindsight health
3. 💡 Sessions for PR creation average only 4min — your /devflow:create-pr skill is efficient
4. 📉 Token usage trending down 15% week-over-week — compaction skills are helping
```

````

### Step 2: Handle authentication and configuration

The skill needs Langfuse API credentials. These should be sourced from:
1. Environment variables: `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST`
2. Devflow config: `~/.config/devflow/config.toml` under a `[langfuse]` section
3. If neither is available, prompt the user for credentials

### Step 3: Update skills registry

Add to `skills/registry.json`:

```json
{
  "name": "traces-summary",
  "path": "devflow-plugin/commands/traces-summary.md",
  "description": "Query Langfuse traces and produce actionable session insights",
  "category": "observability"
}
````

## Acceptance Criteria

- [ ] `/devflow:traces-summary` is available as a command and listed in the skill registry
- [ ] Running it queries the Langfuse API for recent traces (default: last 7 days)
- [ ] Report includes: session count, average duration, total tokens, error rate
- [ ] Report includes: top tools by usage with average latency
- [ ] Report includes: top skills/commands by invocation count
- [ ] Report includes: error hotspots with failure rates and common error messages
- [ ] Report includes: at least 2 actionable recommendations based on the data
- [ ] Report is formatted as a readable terminal table/markdown
- [ ] Graceful handling when Langfuse is unreachable (error message, not crash)
- [ ] Graceful handling when no traces exist in the period (informative message)
- [ ] Time period is configurable (e.g., `$ARGUMENTS` = "last 30 days" or "today")

## Technical Notes

- Langfuse public API docs: `https://langfuse.com/docs/api` — check for the exact endpoint signatures and authentication method
- Authentication: Langfuse uses Basic auth with public/secret key pairs, OR Bearer tokens depending on version. Check the local setup.
- The API may paginate results — handle pagination for `limit > 100` by following `nextPage` tokens
- macOS `date -v-7d` vs Linux `date -d '7 days ago'` — handle both in the curl commands
- Token counts come from Langfuse observations with `type: "GENERATION"` — look for `usage.totalTokens`, `usage.inputTokens`, `usage.outputTokens`
- For skill usage detection, look for traces or observations with metadata containing skill names
- The recommendations engine is heuristic-based — don't over-engineer it. Simple rules like "if error rate > 10%, flag it" and "if same manual action appears in > 5 sessions, suggest a skill" are sufficient
- Consider caching the Langfuse response to avoid hitting the API multiple times during report generation

## Verification

```bash
# 1. Verify Langfuse is accessible
curl -s http://localhost:3100/api/public/traces?limit=1 \
  -H "Authorization: Bearer ${LANGFUSE_PUBLIC_KEY}"
# Expect: JSON response with trace data

# 2. Run the skill
# /devflow:traces-summary
# Expect: Formatted report with session metrics, tool usage, and recommendations

# 3. Test with no data
# (Clear Langfuse or use a time range with no sessions)
# /devflow:traces-summary last 0 days
# Expect: "No traces found for the specified period"

# 4. Test with Langfuse down
# devflow down (stop services)
# /devflow:traces-summary
# Expect: "Could not connect to Langfuse at http://localhost:3100 — is it running?"

# 5. Verify recommendations are actionable
# Review the recommendations section
# Each recommendation should reference specific data points (not generic advice)
```
