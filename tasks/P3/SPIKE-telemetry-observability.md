---
id: SPIKE-telemetry-observability
title: "Telemetry and Observability for Skill/Tool Invocation"
priority: P3
category: spikes
status: open
depends_on: []
estimated_effort: M
files_to_touch: []
---

# Telemetry and Observability for Skill/Tool Invocation

## Context

How can we verify that the right skills, tools, plugins, and MCPs are being called when expected? Currently, there is no systematic way to confirm that skills fire at the right time, that MCP tools are invoked as intended, or that the agent's behavior matches our configured workflows. This spike investigates telemetry and observability options to close this gap.

## Research Questions

1. Can Langfuse traces tell us which skills were invoked per session?
2. Does Claude Code log skill/plugin invocations anywhere (logs, telemetry, debug output)?
3. Can we add instrumentation to our hooks that log to Langfuse when skills fire?
4. Can agent-deck's logging (`[logs]` section) capture skill invocations?
5. Is there a way to set up alerts when expected skills DON'T fire? (e.g., "brainstorming should fire before any implementation but didn't")
6. Can we distinguish between "skill was loaded" and "skill instructions were followed"?
7. What is the performance overhead of adding telemetry to every skill/tool invocation?

## Investigation Steps

1. **Check Langfuse trace structure**
   - What metadata is captured per trace? (model, tokens, latency — but what about tool calls?)
   - Can we see which tools were invoked in a trace?
   - Can we add custom metadata/tags to traces from hooks?
   - Check if Langfuse has a "spans" or "events" concept that could represent skill invocations.

2. **Check agent-deck session logs**
   - What is logged per session in the `[logs]` section?
   - Are MCP tool calls logged with timestamps and arguments?
   - Is there a structured log format we can parse?
   - Can we add custom log entries from hooks?

3. **Check Claude Code native telemetry**
   - Does Claude Code have debug/verbose logging that captures tool calls?
   - Is there a `--debug` or `--verbose` flag that exposes internal state?
   - Check if the Claude Code plugin API exposes invocation events.

4. **Prototype skill invocation logging**
   - Create a hook that fires when a skill is loaded and logs to Langfuse.
   - Test: does the hook fire reliably? What's the latency overhead?
   - Log: skill name, timestamp, session ID, triggering context.

5. **Research negative alerting (missing invocations)**
   - Can Langfuse alert on the absence of an expected event?
   - Could we define "skill policies" (e.g., "brainstorming must fire before implementation") and check compliance post-session?
   - Research: is post-session analysis (batch) more practical than real-time alerting?

6. **Research existing observability tools for LLM agents**
   - LangSmith, Helicone, Braintrust — do any have better skill/tool tracking than Langfuse?
   - Are there open-source alternatives purpose-built for agent observability?

## Expected Deliverables

- **Report on current telemetry data availability**:
  - What data Langfuse captures today (with examples).
  - What data agent-deck logs capture today (with examples).
  - What data Claude Code natively exposes (with examples).

- **Gap analysis**: What telemetry data we NEED but DON'T HAVE, specifically:
  - Skill invocation events (which skill, when, why).
  - Tool call events (which MCP tool, arguments, result summary).
  - Workflow compliance (did the agent follow the expected skill sequence?).

- **Proposed solution for skill invocation tracking**:
  - Architecture: where instrumentation hooks go, where data flows, where it's stored.
  - Implementation plan: what to build, in what order.
  - Estimated effort per component.

- **Proposed alert system for missing expected invocations**:
  - Define "skill policies" format (e.g., YAML rules like `before: [implementation] require: [brainstorming]`).
  - Compliance checker: post-session batch job or real-time monitor?
  - Alert channels: terminal notification, Slack, email, dashboard.

- **Dashboard mockup**: What a "devflow observability dashboard" would look like (even ASCII/text is fine).

## Decision Criteria

- **Low overhead**: Telemetry must not add >100ms latency per skill invocation.
- **Non-intrusive**: Must not require modifying skill files themselves — instrumentation should be in hooks/middleware.
- **Actionable**: Collected data must lead to actionable insights, not just noise.
- **Retroactive**: Should be able to analyze past sessions, not just future ones.
- **Privacy-aware**: Do not log conversation content or sensitive data — only metadata (skill names, timestamps, session IDs).

## Technical Notes

- Langfuse's trace model has Traces → Generations → Spans. Skill invocations could be modeled as Spans within a Generation.
- Consider using OpenTelemetry as the instrumentation standard — it would make the solution vendor-agnostic (swap Langfuse for any OTEL-compatible backend).
- The "skill was loaded" vs "skill was followed" distinction is fundamental. Loading can be tracked mechanically; following requires either LLM self-reporting or output analysis.
- For negative alerting, consider a state machine approach: define expected skill sequences as state machines, feed observed invocations through them, alert on invalid transitions or missing states.
- agent-deck hooks (`pre_session`, `post_session`, `pre_prompt`) are natural instrumentation points.
- Consider a lightweight local SQLite database for session telemetry that can be optionally synced to Langfuse — this enables offline analysis and reduces external API dependency.
