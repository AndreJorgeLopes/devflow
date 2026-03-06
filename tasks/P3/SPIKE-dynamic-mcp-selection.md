---
id: SPIKE-dynamic-mcp-selection
title: "Dynamic MCP Selection and Lazy-Loading"
priority: P3
category: spikes
status: open
depends_on: []
estimated_effort: L
files_to_touch: []
---

# Dynamic MCP Selection and Lazy-Loading

## Context

Currently all MCP servers (Hindsight, etc.) are loaded at session start, consuming context tokens even when idle. Every MCP server registers its tool descriptions into the system prompt, which means unused MCPs still cost tokens on every turn. Research whether we can dynamically add/remove MCPs mid-task to reduce this overhead.

## Research Questions

1. Can you add an MCP server to a running Claude Code session via `agent-deck mcp` commands?
2. Does Claude Code support dynamic MCP registration mid-conversation?
3. Can agent-deck's MCP pool (`[mcp_pool]`) help here — if MCPs are pooled, is their tool description still loaded into context?
4. Could we create an "MCP broker" MCP that has one tool (`get_mcp`) which dynamically connects to other MCPs on demand?
5. Is there a way to reduce the context cost of idle MCP tools? (e.g., hiding tool descriptions until needed)
6. Could the agent request new MCPs from the internet (e.g., from MCP registries like mcp.so) with user permission?

## Investigation Steps

1. Read agent-deck MCP pool docs thoroughly — understand how `[mcp_pool]` works and whether pooled MCPs inject tool descriptions at startup or on demand.
2. Test: start a Claude Code session, then try `agent-deck mcp add` from another terminal — does the running session pick it up?
3. Check if Claude Code has a `/mcp` command or similar for mid-session MCP management.
4. Research MCP registries (mcp.so, Smithery, Glama) for auto-discovery protocols and whether they support dynamic connection.
5. Estimate context token cost per MCP server by counting tool descriptions in the system prompt for each registered MCP.
6. Prototype an "MCP broker" concept — a single MCP with one `get_mcp` tool that dynamically spawns and connects to other MCP servers on demand.
7. Test whether removing an MCP mid-session causes errors or graceful degradation.

## Expected Deliverables

- **Feasibility report**: Can we lazy-load MCPs mid-task? Document what works and what doesn't.
- **If yes**: Proposed architecture for MCP broker/lazy-loading, including sequence diagrams.
- **If no**: Alternative approaches to reduce idle MCP context cost (e.g., MCP rotation, session profiles).
- **Token cost estimates**: Per-MCP server token cost breakdown (tool descriptions, system prompt overhead).
- **Prototype**: If feasible, a minimal MCP broker that can connect to one other MCP on demand.

## Decision Criteria

- **Feasible** if we can add/remove MCPs without restarting the session AND the agent can invoke the newly added tools.
- **Partially feasible** if we can reduce context cost through pooling or description hiding, even if full dynamic loading isn't possible.
- **Not feasible** if MCP registration is strictly a session-start operation with no workaround.
- Token savings must be >20% to justify the added complexity.

## Technical Notes

- Claude Code's MCP integration is based on the Model Context Protocol spec — check the spec for dynamic server registration capabilities.
- agent-deck may have its own layer of MCP management that could be leveraged independently of Claude Code's native support.
- Consider the security implications of dynamically connecting to MCPs from registries — user permission flow is critical.
- The "MCP broker" pattern is similar to a service mesh sidecar — research prior art in that space.
