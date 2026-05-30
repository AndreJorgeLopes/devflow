---
tags: [devflow, visualizations, index, mermaid, excalidraw, style-guide]
---

# Devflow Visualizations

> Architecture diagrams, workflow charts, and integration maps for the devflow ecosystem.
> Diagrams are authored either as Mermaid (default — renderable in VS Code's Mermaid Preview or [mermaid.live](https://mermaid.live)) or as rendered Excalidraw PNGs (opt-in — see the [Excalidraw Diagrams](#excalidraw-diagrams-opt-in-rendered-format) section below).

---

## Navigation

| Category | File | What it shows |
|----------|------|---------------|
| **Architecture** | [[devflow-ecosystem]] | The 5-layer tool ecosystem — Hindsight, Worktrunk, Code Review, Skills, Langfuse |
| **Architecture** | [[code-review-architecture]] | Code review dispatch, check rules pipeline, devflow review dual-mode |
| **Architecture** | runtime-architecture _(future)_ | Docker containers, Homebrew CLIs, config file locations |
| **Architecture** | sync-architecture _(future)_ | Skills/MCP sync flow across delivery targets |
| **Workflows** | [[development-workflow]] | Full SDD workflow: idea to merge request, TDD loop, review gates, phase-handoff spawns |
| **Workflows** | session-lifecycle _(future)_ | Session create → phase-handoff spawn → done → cleanup |
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
| Worktrunk | Green | `#059669` | `worktrunkStyle` |
| Code Review | Amber | `#d97706` | `reviewStyle` |
| Skills/Marketplace | Pink | `#be185d` | `skillsStyle` |
| Langfuse | Cyan | `#0891b2` | `langfuseStyle` |
| Phase-handoff / spawn | Amber variant | `#f59e0b` | `handoffStyle` |
| CLI/Terminal | Gray | `#374151` | `cliStyle` |
| Decision nodes | Dark gray | `#374151` | `decisionStyle` |
| Terminal nodes | Medium gray | `#6b7280` | `terminalStyle` |

### classDef Template

Copy this block into every diagram and apply the relevant classes:

```mermaid
classDef hindsightStyle fill:#7c3aed,color:#fff,stroke:#5b21b6
classDef worktrunkStyle fill:#059669,color:#fff,stroke:#047857
classDef reviewStyle fill:#d97706,color:#fff,stroke:#b45309
classDef skillsStyle fill:#be185d,color:#fff,stroke:#9d174d
classDef langfuseStyle fill:#0891b2,color:#fff,stroke:#0e7490
classDef handoffStyle fill:#f59e0b,color:#fff,stroke:#d97706
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

## Excalidraw Diagrams (opt-in rendered format)

Mermaid is the default. When a project's config sets `"format": "excalidraw"` (via `/devflow:visualizations-config`), or a skill explicitly needs a raster diagram shown inline, diagrams are authored as `.excalidraw` and rendered to PNG via the `/devflow:render-diagram` skill (or the `devflow visualizations render` CLI directly).

**Why Excalidraw:** the PNG renders **inline in a Claude session via the Read tool** (Mermaid source does not), and the `.png` renders natively on GitHub and in the VS Code preview with no extension.

**Pipeline — no browser, no headless Chromium, no MCP:** `.excalidraw → excalidraw-to-svg → @resvg/resvg-js → PNG`. Pure Node; the deps (`canvas`, `excalidraw-to-svg`, `@resvg/resvg-js`) are installed globally (`npm i -g canvas excalidraw-to-svg @resvg/resvg-js`).

**Render:**

```
devflow visualizations render <name>.excalidraw   # writes <name>.svg + <name>.png alongside, prints "PNG <path>"
```

Or invoke `/devflow:render-diagram`, which authors the `.excalidraw`, renders it, **Reads the PNG** to show it inline, and embeds it.

**Display rule:** to show a diagram in-session you **Read the PNG** — it renders inline. A markdown `![](x.png)` embed only shows clickable link text in the Claude app, so embeds are for **persisted docs** (the committed `.png`), not in-session display.

**Embedding in docs:** keep all three artefacts — `.excalidraw` (editable source), `.png`, `.svg` — next to the doc, and embed with a **relative** path + alt text + title:

```markdown
![<alt text>](./<name>.png "<Title>")
```

**Color palette (by component type):**

| Component type | Fill | Stroke |
|----------------|------|--------|
| client / UI | `#a5d8ff` | `#1971c2` |
| API / gateway | `#d0bfff` | `#6741d9` |
| service / compute | `#b2f2bb` | `#2f9e44` |
| datastore / DB | `#ffd8a8` | `#e8590c` |
| cache / queue | `#fcc2d7` | `#c2255c` |
| neutral / external | `#e9ecef` | `#343a40` |

Use `fontFamily: 2` (clean sans) for readable doc diagrams. Never use diamond shapes (arrow binding breaks); each labeled box is a `rectangle` + a separate bound `text` element.

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

_Last updated: 2026-05-28_
