---
id: SPIKE-specialized-agent-projects
title: "Specialized Agent Projects as New Layer"
priority: P3
category: spikes
status: open
depends_on: []
estimated_effort: M
files_to_touch: []
---

# Specialized Agent Projects as New Layer

## Context

Research code-specific agent projects that could add specialized capabilities to our devflow stack. The current 6-layer stack covers broad development workflows, but specialized agents may fill gaps for specific tasks like autonomous issue resolution, advanced git-aware editing, or code review augmentation. The goal is to identify whether a "Layer 7" of specialized agents makes sense and which projects best fit.

## Research Questions

1. Which projects are compatible with Claude Code (not just VS Code)?
2. Which could be installed as Claude Code plugins or MCP servers?
3. Which fill gaps in our current 6-layer stack?
4. What would "Layer 7" look like if we added specialized agents?
5. Can multiple agent projects coexist without conflicting (e.g., competing for git locks, file handles)?
6. What is the maintenance burden of adding each project to the stack?

## Investigation Steps

### Projects to Investigate

1. **oh-my-opencode** (https://github.com/code-yeongyu/oh-my-opencode)
   - Does it work with Claude Code? What specialized behaviors does it add?
   - Is it a wrapper, plugin, or standalone tool?
   - Test installation and compatibility with our current setup.

2. **Aider** (https://github.com/paul-gauthier/aider)
   - Git-aware AI coding assistant. Could it complement Claude Code for specific tasks?
   - Test: can Aider and Claude Code share a git repo without conflicts?
   - Evaluate its diff-based editing approach vs Claude Code's edit tool.

3. **SWE-agent** (https://github.com/princeton-nlp/SWE-agent)
   - Autonomous issue resolution. Could it handle Jira/Linear tickets autonomously?
   - Evaluate its scaffolding and sandboxing approach.
   - Could it be triggered by `devflow work` for specific ticket types?

4. **Cline/Continue**
   - Already using Continue.dev for review. What else can it do?
   - Investigate Cline's autonomous capabilities.
   - Check for MCP server compatibility.

5. **Cursor-like features**
   - Any plugins that add Cursor-style features (tab completion, inline edits) to our terminal workflow?
   - Research terminal-native autocomplete/inline-edit tools.

6. **Claude Code plugins ecosystem**
   - Browse the plugin marketplace for relevant additions.
   - Check community plugins, hooks, and extensions.

### Evaluation Process

1. For each project: install, test basic functionality, note compatibility issues.
2. Map each project to gaps in our current stack.
3. Assess integration effort (hours/days) for top candidates.
4. Test coexistence: run 2+ agents on the same repo simultaneously.

## Expected Deliverables

- **Comparison table**: Project name, compatibility with Claude Code, what it adds, integration effort (S/M/L), maintenance burden.
- **Gap analysis**: Map each project to gaps in the current 6-layer stack.
- **Recommendation**: Top 2-3 projects to integrate, ranked by value/effort ratio.
- **For each recommendation**: Proposed integration approach (plugin, MCP server, standalone sidecar, or devflow subcommand).
- **"Layer 7" architecture sketch**: If we add specialized agents, how do they fit into the existing stack?

## Decision Criteria

- **High value**: Fills a clear gap in the current stack that causes friction today.
- **Low friction**: Can be integrated without major changes to existing workflows.
- **Compatible**: Works alongside Claude Code without conflicts.
- **Maintainable**: Active project with good documentation; not a one-person hobby project.
- **Terminal-native**: Must work in terminal — VS Code-only projects are deprioritized.

## Technical Notes

- Some projects (Aider, SWE-agent) use their own LLM connections — consider token cost implications of running multiple LLM-powered tools.
- Git lock contention is a real risk when multiple agents touch the same repo — investigate file-level locking strategies.
- Consider using git worktrees (via worktrunk) to give different agents isolated working copies.
- oh-my-opencode appears to be an OpenCode customization framework — verify it isn't Claude Code-incompatible by design.
