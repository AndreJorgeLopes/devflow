# Devflow Task Board

> Task tickets organized by priority. Each ticket is written as an LLM-optimized prompt — an AI agent reading the ticket should be able to execute it without additional context. Category is encoded in the filename prefix (BUGS-, ARCH-, FEAT-, SPIKE-, POLISH-).

## Structure

```
tasks/
├── P0/     # Critical — fix immediately (bugs + blocking architecture)
├── P1/     # High — architecture integrity (fix this week)
├── P2/     # Medium — new features (plan and schedule)
├── P3/     # Low — research spikes (explore when capacity allows)
└── P4/     # Low — polish (do when everything else is done)
```

## Category Prefixes

| Prefix | Meaning |
|--------|---------|
| `BUGS-` | Broken/blocking issues |
| `ARCH-` | Architecture/structural changes |
| `FEAT-` | New features and capabilities |
| `SPIKE-` | Research/investigation |
| `POLISH-` | Cosmetic/documentation |

---

## All Tickets

### P0 — Critical (fix now)

| ID | Title | Category | Effort | Status |
|----|-------|----------|--------|--------|
| [BUGS-fix-help-escape-chars](P0/BUGS-fix-help-escape-chars.md) | Fix Help CLI Escape Character Display | bugs | S | open |
| [BUGS-fix-docker-compose-warnings](P0/BUGS-fix-docker-compose-warnings.md) | Fix Docker Compose Warnings | bugs | M | open |
| [BUGS-fix-hindsight-startup-timeout](P0/BUGS-fix-hindsight-startup-timeout.md) | Fix Hindsight Startup Timeout | bugs | L | open |
| [BUGS-fix-docker-daemon-guidance](P0/BUGS-fix-docker-daemon-guidance.md) | Fix Docker Daemon Startup Guidance | bugs | M | open |
| [ARCH-skills-mcp-sync](P0/ARCH-skills-mcp-sync.md) | Single Source of Truth Sync for Skills, MCPs, Config | arch | XL | open |
| [ARCH-visualization-update-hook](P0/ARCH-visualization-update-hook.md) | Auto-Update Visualizations After Task Completion | arch | L | open |

### P1 — Architecture (system correctness)

| ID | Title | Effort | Depends On | Status |
|----|-------|--------|------------|--------|
| [ARCH-agent-spawning-consistency](P1/ARCH-agent-spawning-consistency.md) | Agent Spawning Consistency Through Agent-Deck | M | — | open |
| [ARCH-forgotten-items-previous-impl](P1/ARCH-forgotten-items-previous-impl.md) | Forgotten Items From Previous Implementation | L | — | open |
| [ARCH-update-actual-configs](P1/ARCH-update-actual-configs.md) | Update Actual Configs (Not Just Templates) | M | — | open |
| [ARCH-skills-registry-global-sources](P1/ARCH-skills-registry-global-sources.md) | Skills Registry to Global Sources + MCP Pool | M | update-actual-configs | open |
| [ARCH-global-vs-per-project-configs](P1/ARCH-global-vs-per-project-configs.md) | Global vs Per-Project Configs | M | — | open |
| [ARCH-devflow-work-entry-point](P1/ARCH-devflow-work-entry-point.md) | Development Workflow Entry Point (`devflow work`) | L | agent-spawning, forgotten-items | open |
| [ARCH-session-task-completion](P1/ARCH-session-task-completion.md) | Session/Task Completion Command (`devflow done`) | L | devflow-work | open |
| [ARCH-pr-creation-vcs-detection](P1/ARCH-pr-creation-vcs-detection.md) | PR Creation With Correct VCS Tool | S | — | open |

### P2 — Features (new capabilities)

| ID | Title | Effort | Status |
|----|-------|--------|--------|
| [FEAT-interactive-hindsight-seeding](P2/FEAT-interactive-hindsight-seeding.md) | Interactive Hindsight Seeding on `devflow up` | M | open |
| [FEAT-self-learning-mechanisms](P2/FEAT-self-learning-mechanisms.md) | Self-Learning Mechanisms (Agent Memory Hooks) | L | open |
| [FEAT-context-compaction-skill](P2/FEAT-context-compaction-skill.md) | Context Compaction Skill | M | open |
| [FEAT-refactor-skill](P2/FEAT-refactor-skill.md) | Refactor Skill (Multi-Agent Refactoring) | XL | open |
| [FEAT-langfuse-traces-tldr](P2/FEAT-langfuse-traces-tldr.md) | Langfuse Traces TLDR Skill | M | open |
| [FEAT-lazygit-lazydocker-wrappers](P2/FEAT-lazygit-lazydocker-wrappers.md) | Lazygit and Lazydocker CLI Wrappers | S | open |

### P3 — Spikes (research)

| ID | Title | Effort | Status |
|----|-------|--------|--------|
| [SPIKE-dynamic-mcp-selection](P3/SPIKE-dynamic-mcp-selection.md) | Dynamic MCP Selection and Lazy-Loading | L | open |
| [SPIKE-specialized-agent-projects](P3/SPIKE-specialized-agent-projects.md) | Specialized Agent Projects as New Layer | M | open |
| [SPIKE-kanban-board-integration](P3/SPIKE-kanban-board-integration.md) | Kanban Board Integration (Vibe-Kanban) | L | open |
| [SPIKE-task-management-export](P3/SPIKE-task-management-export.md) | Task Management Export Format | M | open |
| [SPIKE-telemetry-observability](P3/SPIKE-telemetry-observability.md) | Telemetry for Skill/Tool Invocation | M | open |

### P4 — Polish

| ID | Title | Effort | Status |
|----|-------|--------|--------|
| [POLISH-readme-improvement](P4/POLISH-readme-improvement.md) | README Improvement | M | open |
| [POLISH-yadm-tracking](P4/POLISH-yadm-tracking.md) | YADM Tracking for All Configs | M | open |
| [POLISH-docker-sandbox-adr](P4/POLISH-docker-sandbox-adr.md) | Document Docker Disabled Decision (ADR) | S | open |

---

## Dependency Graph

```
BUGS-fix-help-escape-chars ──────────┐
BUGS-fix-docker-compose-warnings ────┤
BUGS-fix-hindsight-startup-timeout ──┤──→ ARCH-update-actual-configs ──→ ARCH-skills-registry-global-sources
BUGS-fix-docker-daemon-guidance ─────┘                                          │
                                                                                ▼
ARCH-skills-mcp-sync ◄──────────────────────────────────────────────────────────┘
ARCH-visualization-update-hook ── standalone

ARCH-agent-spawning-consistency ─┐
ARCH-forgotten-items-previous ───┼──→ ARCH-devflow-work-entry-point ──→ ARCH-session-task-completion
                                 │
ARCH-global-vs-per-project ──────┘
ARCH-pr-creation-vcs-detection ── standalone

FEAT-* ── all standalone, can be parallelized
SPIKE-* ── all standalone research
POLISH-* ── do last
```

## Execution Order (recommended)

1. **Batch 1 (parallel):** BUGS-fix-help-escape-chars, BUGS-fix-docker-compose-warnings, BUGS-fix-docker-daemon-guidance, ARCH-pr-creation-vcs-detection
2. **Batch 2:** BUGS-fix-hindsight-startup-timeout (depends on compose fix)
3. **Batch 3 (parallel):** ARCH-agent-spawning-consistency, ARCH-forgotten-items, ARCH-update-actual-configs, ARCH-global-vs-per-project, ARCH-visualization-update-hook
4. **Batch 4:** ARCH-skills-registry-global-sources (after update-actual-configs), ARCH-devflow-work-entry-point (after agent-spawning + forgotten-items)
5. **Batch 5:** ARCH-skills-mcp-sync (after skills-registry), ARCH-session-task-completion (after devflow-work)
6. **Batch 6 (parallel):** All P2 features
7. **Batch 7 (parallel):** All P3 spikes
8. **Batch 8:** P4 polish

---

_Total: 28 tickets | 6 P0 | 8 P1 | 6 P2 | 5 P3 | 3 P4_
