---
tags: [devflow, visualizations, index, mermaid, style-guide]
---

# Devflow Visualizations

> Architecture diagrams, workflow charts, and integration maps for the devflow ecosystem.
> All diagrams are Mermaid-renderable in VS Code (Mermaid Preview extension) or [mermaid.live](https://mermaid.live).

---

## Navigation

| Category | File | What it shows |
|----------|------|---------------|
| **Architecture** | [[devflow-ecosystem]] | The 6-layer tool ecosystem — Hindsight, Agent Deck, Worktrunk, Code Review, Skills, Langfuse |
| **Architecture** | [[code-review-architecture]] | Code review dispatch, check rules pipeline, devflow review dual-mode |
| **Architecture** | runtime-architecture _(future)_ | Docker containers, Homebrew CLIs, config file locations |
| **Architecture** | sync-architecture _(future)_ | Skills/MCP sync flow across 7 targets |
| **Workflows** | [[development-workflow]] | Full SDD workflow: idea to merge request, TDD loop, review gates |
| **Workflows** | devflow-work-flow _(future)_ | The `devflow work` command flow |
| **Workflows** | session-lifecycle _(future)_ | Session create → conductor → done → cleanup |
| **Integrations** | agent-deck-integration _(future)_ | How agent-deck connects to everything |
| **Integrations** | hindsight-data-flow _(future)_ | Memory recall/retain/reflect patterns |
| **Integrations** | langfuse-trace-flow _(future)_ | What gets traced and where |
| **Decisions** | _(created as needed)_ | Visual ADRs when diagrams help explain decisions |

---

## Style Guide

All visualization files in this repository must follow these conventions.

### Frontmatter

Every file starts with YAML frontmatter:

```yaml
---
tags: [devflow, <category>, <specific-tags>]
related: ["[[other-file]]"]
---
```

### Mermaid Init Block

Every mermaid diagram starts with consistent spacing configuration:

```
%%{init: {'flowchart': {'rankSpacing': 50, 'nodeSpacing': 30, 'diagramPadding': 15}}}%%
```

### Color Palette

Consistent across all diagrams — each devflow component has a fixed color:

| Component | Color | Hex | classDef name |
|-----------|-------|-----|---------------|
| Hindsight | Purple | `#7c3aed` | `hindsightStyle` |
| Agent Deck | Blue | `#3b82f6` | `agentDeckStyle` |
| Worktrunk | Green | `#059669` | `worktrunkStyle` |
| Code Review | Amber | `#d97706` | `reviewStyle` |
| Skills/Marketplace | Pink | `#be185d` | `skillsStyle` |
| Langfuse | Cyan | `#0891b2` | `langfuseStyle` |
| Conductor | Amber variant | `#f59e0b` | `conductorStyle` |
| CLI/Terminal | Gray | `#374151` | `cliStyle` |
| Decision nodes | Dark gray | `#374151` | `decisionStyle` |
| Terminal nodes | Medium gray | `#6b7280` | `terminalStyle` |

### classDef Template

Copy this block into every diagram and apply the relevant classes:

```mermaid
classDef hindsightStyle fill:#7c3aed,color:#fff,stroke:#5b21b6
classDef agentDeckStyle fill:#3b82f6,color:#fff,stroke:#1e40af
classDef worktrunkStyle fill:#059669,color:#fff,stroke:#047857
classDef reviewStyle fill:#d97706,color:#fff,stroke:#b45309
classDef skillsStyle fill:#be185d,color:#fff,stroke:#9d174d
classDef langfuseStyle fill:#0891b2,color:#fff,stroke:#0e7490
classDef conductorStyle fill:#f59e0b,color:#fff,stroke:#d97706
classDef cliStyle fill:#374151,color:#fff,stroke:#1f2937
classDef decisionStyle fill:#374151,color:#fff,stroke:#1f2937
classDef terminalStyle fill:#6b7280,color:#fff,stroke:#4b5563
```

### File Naming

- Use lowercase kebab-case: `devflow-ecosystem.md`, not `DevflowEcosystem.md`
- No numeric prefixes — ordering is by category folder, not filename
- Keep names descriptive but concise

### Section Structure

Each visualization file should have:
1. Frontmatter (tags + related links)
2. Title with one-line description
3. Horizontal rule between sections
4. Numbered section headings
5. One mermaid diagram per section (avoid putting multiple diagrams in one section)

---

## Folder Structure

```
visualizations/
├── README.md              ← you are here
├── architecture/          # System architecture diagrams
├── workflows/             # Process flow diagrams
├── integrations/          # Tool-specific integration diagrams
└── decisions/             # Visual ADRs
```

---

## Updating Visualizations

Use the `/devflow:update-visualizations` command after making changes that affect the architecture:

```
/devflow:update-visualizations "Added new CLI command for X"
```

The command will:
1. Analyze your recent git changes
2. Determine which diagrams are affected
3. Update existing diagrams or create new ones
4. Update this index if new files were created
5. Commit the changes

---

_Last updated: 2026-03-10_
