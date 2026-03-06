---
id: SPIKE-kanban-board-integration
title: "Kanban Board Integration (Vibe-Kanban + Linear/Jira)"
priority: P3
category: spikes
status: open
depends_on: []
estimated_effort: L
files_to_touch: []
---

# Kanban Board Integration (Vibe-Kanban + Linear/Jira)

## Context

Research integrating a Kanban board that connects to Linear and Jira, shows open tasks, and can trigger `devflow work` from task selection. The goal is a unified terminal-based task view that bridges external project management tools with our local development workflow, enabling a seamless flow from "pick a task" to "start coding."

## Research Questions

1. Can Vibe-Kanban connect to Linear/Jira APIs, or is it local-only?
2. Does Taskwarrior have mature Linear/Jira plugins that support bidirectional sync?
3. Is the Linear CLI feature-complete enough to replace a Kanban UI, or is it query-only?
4. Can jira-cli trigger custom commands (like `devflow work`) on status transitions?
5. What is the latency of bidirectional sync for each approach? (Real-time vs polling)
6. Can agent-deck conductor notifications be triggered from Kanban column transitions?

## Investigation Steps

### Projects to Investigate

1. **Vibe-Kanban** (https://github.com/BloopAI/vibe-kanban)
   - Install and test locally.
   - Check if it supports external data sources or is file/local-only.
   - Evaluate TUI quality and customizability.
   - Check if column transitions can trigger shell commands (hooks).

2. **Taskwarrior** (https://taskwarrior.org/)
   - Research plugin ecosystem for Linear/Jira integrations.
   - Evaluate hook system — can hooks trigger `devflow work`?
   - Test bidirectional sync reliability.
   - Assess learning curve and configuration complexity.

3. **Linear CLI** (https://github.com/linear/linear-cli)
   - Install and test basic operations (list issues, update status).
   - Check if it supports webhooks or event-driven workflows.
   - Evaluate whether it could feed into a local Kanban display.

4. **jira-cli** (https://github.com/ankitpokhrel/jira-cli)
   - Install and test basic operations.
   - Check for hook/event support on status transitions.
   - Evaluate TUI board view quality.

### Integration Requirements Testing

5. Test vendor-agnostic abstraction — can we create a common interface that works with both Linear and Jira?
6. Prototype: select a task from a board → extract ticket ID → run `devflow work <ticket-id>` → auto-create branch.
7. Test notification integration with agent-deck conductor.
8. Evaluate mobile notification options (push notifications when agent needs attention).

## Expected Deliverables

- **Feasibility report** for each investigated project, covering:
  - External API connectivity (Linear, Jira)
  - Hook/event support for triggering devflow commands
  - Bidirectional sync capability and reliability
  - TUI quality and usability
- **Recommended approach**: Which tool(s) to use and how to integrate with devflow.
- **Proposed command spec** for `devflow board` or `devflow tasks`:
  - `devflow board` — open Kanban TUI with tasks from configured source
  - `devflow board sync` — pull/push task updates
  - `devflow tasks list [--source linear|jira|local]` — list tasks
  - `devflow tasks pick <id>` — select task and start `devflow work`
- **Integration points** with existing devflow commands (`devflow work`, `devflow done`).
- **Notification architecture** for agent-needs-attention alerts.

## Decision Criteria

- **Vendor-agnostic**: Must support at least Linear and Jira without major code changes. Ideally pluggable.
- **Terminal-native**: Must work in the terminal — no browser-based solutions.
- **Bidirectional**: Local changes should propagate to the external tool and vice versa.
- **Low latency**: Task selection to `devflow work` should take <5 seconds.
- **Hook support**: Column/status transitions must be able to trigger shell commands.
- **Offline capable**: Should work offline with local state, syncing when connectivity returns.

## Technical Notes

- Consider a layered architecture: abstract task source (Linear, Jira, local YAML) → common task model → Kanban renderer → devflow integration.
- Bidirectional sync is notoriously hard — research conflict resolution strategies. Last-write-wins may be acceptable for status fields but dangerous for descriptions.
- agent-deck conductor notifications could use OS-level notifications (terminal-notifier on macOS) or a webhook to a mobile push service.
- The local task board (`tasks/` directory with YAML frontmatter) is already a data source — it should be a first-class citizen alongside Linear/Jira.
- This spike has a dependency relationship with SPIKE-P3-004 (Task Management Export Format) — coordinate findings.
