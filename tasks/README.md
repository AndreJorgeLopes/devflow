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
| [ARCH-visualization-update-hook](P0/ARCH-visualization-update-hook.md) | Auto-Update Visualizations After Task Completion | arch | L | open |

### P1 — Architecture (system correctness)

| ID | Title | Effort | Depends On | Status |
|----|-------|--------|------------|--------|
| [ARCH-detached-head-worktrees](P1/ARCH-detached-head-worktrees.md) | Never Lock Main Branch in Worktrees | M | — | open |
| [ARCH-global-vs-per-project-configs](P1/ARCH-global-vs-per-project-configs.md) | Global vs Per-Project Configs | M | — | open |
| [ARCH-pr-creation-vcs-detection](P1/ARCH-pr-creation-vcs-detection.md) | PR Creation With Correct VCS Tool | S | — | open |
| [ARCH-stop-hook-finish-feature-removal](P1/ARCH-stop-hook-finish-feature-removal.md) | Remove finish-feature From Stop Hook | S | — | open |
| [ARCH-testing-foundation](P1/ARCH-testing-foundation.md) | Testing Foundation (bats-core + helpers) | M | — | open |
| [ARCH-testing-infrastructure](P1/ARCH-testing-infrastructure.md) | Testing Infrastructure (mocks + fixtures) | M | testing-foundation | open |
| [ARCH-testing-unit-tests](P1/ARCH-testing-unit-tests.md) | Unit Test Coverage for lib/ | L | testing-infrastructure | open |
| [ARCH-testing-integration](P1/ARCH-testing-integration.md) | Integration Tests for CLI commands | L | testing-unit-tests | open |
| [ARCH-testing-e2e](P1/ARCH-testing-e2e.md) | End-to-End Workflow Tests | L | testing-integration | open |
| [ARCH-testing-ci-pipeline](P1/ARCH-testing-ci-pipeline.md) | CI Pipeline (GitHub Actions) | M | testing-e2e | open |
| [FEAT-lsp-integration-devflow-init](P1/FEAT-lsp-integration-devflow-init.md) | LSP Integration in devflow init | M | — | open |

### P2 — Features (new capabilities)

| ID | Title | Effort | Status |
|----|-------|--------|--------|
| [FEAT-interactive-hindsight-seeding](P2/FEAT-interactive-hindsight-seeding.md) | Interactive Hindsight Seeding on `devflow up` | M | open |
| [FEAT-self-learning-mechanisms](P2/FEAT-self-learning-mechanisms.md) | Self-Learning Mechanisms (Agent Memory Hooks) | L | open |
| [FEAT-refactor-skill](P2/FEAT-refactor-skill.md) | Refactor Skill (Multi-Agent Refactoring) | XL | open |
| [FEAT-langfuse-traces-tldr](P2/FEAT-langfuse-traces-tldr.md) | Langfuse Traces TLDR Skill | M | open |
| [FEAT-lazygit-lazydocker-wrappers](P2/FEAT-lazygit-lazydocker-wrappers.md) | Lazygit and Lazydocker CLI Wrappers | S | open |

### P3 — Spikes (research)

| ID | Title | Effort | Status |
|----|-------|--------|--------|
| [SPIKE-specialized-agent-projects](P3/SPIKE-specialized-agent-projects.md) | Specialized Agent Projects as New Layer | M | open |
| [SPIKE-kanban-board-integration](P3/SPIKE-kanban-board-integration.md) | Kanban Board Integration (Vibe-Kanban) | L | open |
| [SPIKE-task-management-export](P3/SPIKE-task-management-export.md) | Task Management Export Format | M | open |
| [SPIKE-telemetry-observability](P3/SPIKE-telemetry-observability.md) | Telemetry for Skill/Tool Invocation | M | open |
| [SPIKE-hooks-improvement-opportunities](P3/SPIKE-hooks-improvement-opportunities.md) | Hooks Improvement Opportunities | M | open |

### P4 — Polish

| ID | Title | Effort | Status |
|----|-------|--------|--------|
| [POLISH-readme-improvement](P4/POLISH-readme-improvement.md) | README Improvement | M | open |

---

## Dependency Graph

```
BUGS-fix-help-escape-chars ──────────┐
BUGS-fix-docker-compose-warnings ────┤── standalone bug fixes
BUGS-fix-hindsight-startup-timeout ──┤   (compose fix unblocks hindsight)
BUGS-fix-docker-daemon-guidance ─────┘

ARCH-visualization-update-hook ───── standalone
ARCH-detached-head-worktrees ─────── standalone
ARCH-global-vs-per-project-configs ─ standalone
ARCH-pr-creation-vcs-detection ───── standalone
ARCH-stop-hook-finish-feature-removal standalone

ARCH-testing-foundation
  ↓
ARCH-testing-infrastructure
  ↓
ARCH-testing-unit-tests
  ↓
ARCH-testing-integration
  ↓
ARCH-testing-e2e
  ↓
ARCH-testing-ci-pipeline

FEAT-lsp-integration-devflow-init ── standalone

FEAT-* ── all standalone, can be parallelized
SPIKE-* ── all standalone research
POLISH-* ── do last
```

## Execution Order (recommended)

1. **Batch 1 (parallel):** BUGS-fix-help-escape-chars, BUGS-fix-docker-compose-warnings, BUGS-fix-docker-daemon-guidance, ARCH-pr-creation-vcs-detection, ARCH-stop-hook-finish-feature-removal
2. **Batch 2:** BUGS-fix-hindsight-startup-timeout (depends on compose fix)
3. **Batch 3 (parallel):** ARCH-visualization-update-hook, ARCH-detached-head-worktrees, ARCH-global-vs-per-project-configs, ARCH-testing-foundation
4. **Batch 4 (testing chain):** testing-infrastructure → testing-unit-tests → testing-integration → testing-e2e → testing-ci-pipeline (each depends on previous)
5. **Batch 5 (parallel):** All P2 features + FEAT-lsp-integration-devflow-init
6. **Batch 6 (parallel):** All P3 spikes
7. **Batch 7:** P4 polish

---

_Total: 23 tickets | 5 P0 | 11 P1 | 5 P2 | 5 P3 | 1 P4_

_Last revised: 2026-05-28 (deprecation cleanup — 10 stale agent-deck/superpowers-era tasks removed)_
