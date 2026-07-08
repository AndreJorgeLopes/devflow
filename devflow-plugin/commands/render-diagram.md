---
description: [0.17.2] Create and render an Excalidraw diagram from a description or codebase analysis — exports to PNG via a pure-node pipeline (no browser/MCP), shows it inline via the Read tool, and embeds it in docs. Use when asked to diagram, visualize, or draw an architecture/flow, or when another skill needs a rendered diagram.
---

# Render Diagram

Single purpose: turn a description (or a target to analyze) into a **rendered Excalidraw diagram**, SHOW it inline via the Read tool, and — when a destination doc is given — persist the PNG and embed it.

This is the canonical way devflow surfaces diagrams. Other skills (`spec-feature`, `codebase-walkthrough`, `update-visualizations`, `architecture-decision`) call this skill instead of hand-rolling diagrams.

> **Diagram complexity** — before drawing, rate it:
> - 🟢 **simple** — linear / ≤4 nodes → plain ASCII is fine.
> - 🟡 **moderate** — fork-join, 5–8 nodes, or one crossing → OFFER a rendered Excalidraw (the **render-diagram** skill).
> - 🔴 **complex** — bidirectional, multi-lane, >8 nodes, or cycles → render with the **render-diagram** skill AND show it inline via the Read tool.

## Preflight (dependency check)

Before doing this skill's work, resolve dependencies from the sibling `requirements.json`:

1. Read `requirements.json` next to this SKILL.md. If absent, skip preflight (no declared deps).
2. If `devflow` is on PATH, run `devflow deps check render-diagram` and use its report. Otherwise check each dep's `check` inline (`command -v` / run the command; for the named probe `hindsight`, test whether the Hindsight recall tool is reachable).
3. **Required dep missing** → STOP. Report the dep `name`, `why`, and `install` hint. Do not continue.
4. **Optional dep missing** → ask via `AskUserQuestion` (header "Optional dep"): **Provide an alternative** (path/command/endpoint) · **Continue without** (apply the dep's `degrade`) · **Abort**. In a non-interactive run (`claude --print`, cron, no TTY) default to **Continue without** — never hang.
5. Carry the chosen optional-dep behavior through the rest of the run.

## What you produce
- `<name>.excalidraw` — editable source (opens in excalidraw.com or the VS Code extension)
- `<name>.svg` + `<name>.png` — exported renders, saved alongside the source
- the PNG shown **inline in this session** via the Read tool (the primary deliverable)
- when persisting to a doc: a markdown embed `![alt](./<name>.png "Title")`

## How rendering works (no browser / no MCP)
Export runs a pure-node pipeline — `.excalidraw → excalidraw-to-svg → @resvg/resvg-js → PNG` — invoked through the devflow CLI:

```
devflow visualizations render <file>.excalidraw [output-basename]
```

No Playwright, no headless Chromium, no MCP server. The deps (`canvas`, `excalidraw-to-svg`, `@resvg/resvg-js`) are auto-provisioned by `render-deps.sh` (existing globals → `~/.devflow/render-deps` cache → consent install, no `-g`/sudo). The command prints `PNG <abspath>` as its final stdout line — capture it.

## Step 1: Determine what to diagram
From `$ARGUMENTS` (or the calling skill's context), establish the components (nodes) and relationships (edges). Three input modes:
- **Description given** — use the components/relationships described.
- **Target to analyze** ("diagram this codebase / feature / diff") — discover components with Glob/Grep/Read (entry points, services, datastores, APIs, queues) before drawing.
- **Existing `.excalidraw`** — skip to Step 3 and just render it.

Keep diagrams focused: 4–12 nodes. If the system is larger, pick ONE coherent view (request flow, data flow, deploy topology) rather than cramming everything in.

## Step 2: Author the `.excalidraw`
Author a valid `.excalidraw` JSON file using the bundled authoring references in this skill's **`references/`** directory — `json-format.md` (element schema + text binding), `arrows.md` (routing + edge bindings), `colors.md` (palette), `examples.md` (complete JSON templates + layout patterns), `validation.md` (pre-write checklist). Read the ones you need, then generate the JSON. (These references are vendored from the MIT-licensed `ooiyeefei/ccc` excalidraw skill — see `references/SOURCE.md`.)

Quick essentials (the must-knows, also covered in the references):
- Each labeled box = **TWO** elements: a `rectangle` with `boundElements:[{ "type":"text","id":"..." }]` AND a separate `text` element whose `containerId` points back to the rectangle. A label is never just a property of the shape.
- Arrows: `type:"arrow"` with `points`, `startBinding`/`endBinding` `{ elementId, focus:0, gap:4 }`, `endArrowhead:"arrow"`. For right-angle routes use multi-segment `points` plus `"elbowed": true` and `"roundness": null`.
- Never use diamond shapes — arrow binding breaks on them.
- Color by component type:
  - client / UI → fill `#a5d8ff`, stroke `#1971c2`
  - API / gateway → fill `#d0bfff`, stroke `#6741d9`
  - service / compute → fill `#b2f2bb`, stroke `#2f9e44`
  - datastore / DB → fill `#ffd8a8`, stroke `#e8590c`
  - cache / queue → fill `#fcc2d7`, stroke `#c2255c`
  - neutral / external → fill `#e9ecef`, stroke `#343a40`
- Top level: `"type":"excalidraw"`, `"version":2`, `"appState":{ "viewBackgroundColor":"#ffffff" }`, `"files":{}`.
- **Always use `"fontFamily":2` (Helvetica/sans) for text that must render.** `fontFamily:1` (Excalidraw's hand-drawn "Virgil") is NOT a system font, so resvg falls back to a different face — the measured layout and the drawn glyphs diverge and text looks broken/mis-sized. Sketchy *boxes* (`"roughness":1`) are fine; only the font must be `2`.
- **Bound-text centering is automatic.** The exporter re-centers every container-bound text (a `text` with `containerId` set) inside its box at render time, so you don't need exact text `x/y` — just give each label a `containerId` and a roughly-right box. Standalone text (no `containerId` — captions, titles, arrow labels) renders at its literal `x/y`, so position those yourself. Size boxes tall enough for the text (`lines × fontSize × 1.25`); the exporter warns but will NOT grow a box (growing would disconnect bound arrows).
- **Dark mode:** set `appState.viewBackgroundColor` to a dark colour (e.g. `#1f2428`); the exporter renders on it (or pass `--bg <color>`). Keep node fills as LIGHT pastels with dark in-node text, and make canvas-level text (title, captions, arrow labels) light — never leave them default near-black on a dark canvas.

Write the file to:
- a **persisted** location (next to the target doc, or the project's visualizations path) when the diagram should live in docs, OR
- a **scratch** path (e.g. `.devflow/diagrams/<name>.excalidraw`) for in-session-only display.

## Step 3: Render

The render deps (`canvas`, `excalidraw-to-svg`, `@resvg/resvg-js`) are auto-provisioned by `render-deps.sh` (existing globals → `~/.devflow/render-deps` cache → consent install, no `-g`/sudo). If they may be missing, ask the user **once** via `AskUserQuestion` whether to install them; on yes, set `DEVFLOW_RENDER_ASSUME_YES=1` on the render command so the resolver installs non-interactively instead of blocking on a `read` prompt (which EOFs to "n" in a non-TTY Bash tool / `claude --print` / cron).

- If `devflow` is on PATH:
  ```
  DEVFLOW_RENDER_ASSUME_YES=1 devflow visualizations render <path>/<name>.excalidraw
  ```
- Else (standalone `devflow-diagrams` flow install, no `bin/devflow` on PATH):
  ```
  DEVFLOW_RENDER_ASSUME_YES=1 bash "$SKILL_DIR/render.sh" <path>/<name>.excalidraw
  ```

(If the user declined the install, do NOT set the var — the resolver returns non-zero and you report the missing deps.) Both write `<name>.svg` + `<name>.png` alongside the source and print `PNG <abspath>` as the final stdout line. Capture that path, then SHOW it (Step 4).

## Step 4: SHOW it (mandatory)

**Read the rendered `.png` in its OWN turn — the only tool call in that turn, with a line of text before it.** This is the primary, reliable, full-resolution display path: the harness renders the PNG file directly, so there is no size limit and the image is sharp.

**Do NOT batch the image Read** in the same turn/block as the render Bash (or any other tool). When grouped, the harness suppresses the inline image preview and the user sees nothing — this is the single most common "it didn't show" cause. One Read, alone, per image.

A markdown image embed only shows clickable link text — never rely on it for display.

**Do NOT use `mcp__visualize__show_widget` for these diagrams** (empirically tested, 2026-06):
- **Inline SVG → broken.** The excalidraw export uses rough.js multi-stroke paths; the widget's SVG renderer drops arrows/borders (randomly, even with `roughness:0` single strokes). Sizing is also wrong unless you strip the fixed `width`/`height` for `width="100%"`.
- **`<img>` data-URI → works but impractical.** A raster (`<img src="data:image/...">`) renders fully, but the base64 must pass through the agent's context to reach `widget_code`, and the Read tool truncates base64 over ~22KB. At a resolution that fits the cap the image is visibly blurry (small source upscaled to the container); a sharp version is too large to embed. AVIF is the most efficient codec here (≈⅓ of PNG) if a widget is ever unavoidable — a ~450px-wide AVIF fits and is tolerable — but it is still strictly worse than the standalone PNG Read.

So: always display via the standalone PNG Read above. `show_widget` is not a fit for render-diagram output.

## Step 5: Persist + embed (only when a destination doc is given)
When the diagram belongs in a doc (spec, ADR, walkthrough, README):
1. Keep `<name>.excalidraw`, `<name>.svg`, and `<name>.png` next to the doc (or in the configured visualizations path).
2. Embed in the markdown with a **relative** path, alt text, and a title:
   ```
   ![<concise alt text>](./<name>.png "<Title>")
   ```
3. Commit all three artefacts with the doc — `.excalidraw` is the editable source, `.png` is what renders on GitHub / VS Code, `.svg` is the vector export.

Never embed the raw `.excalidraw` JSON in prose, and never rely on a markdown embed for in-session display — that is what Step 4's Read is for.

## ELI5 mode (explain-it-simply)

Trigger when the user asks to explain a diagram "like I'm five" / "simply" / "ELI5", or wants a teaching diagram. ELI5 mode is **additive, not a replacement** — it shows the friendly version AND keeps the real vocabulary.

**Produce TWO files, show ONE:**
1. `<name>.excalidraw` — the normal **technical** diagram (real terms). Render it and keep it in the folder.
2. `<name>-eli5.excalidraw` — the ELI5 diagram. Render it and **Read only this one inline** (Step 4) — it is the version the user sees in-session.

The technical file is the durable reference; the ELI5 file is the explainer. Both are committed when persisting to a doc.

**The dual-label rule (non-negotiable):** every node carries BOTH labels —
- the **kid word** as the node's bound label (e.g. "time-out box"), and
- the **real tech term** as a grey caption directly beneath the box (e.g. "dead-letter queue (DLQ) · kept 14 days").

Whenever you replace a technical word with a plain one, the technical word MUST still appear in the grey caption, so the reader learns the simple model AND the real vocabulary. Never drop the real term.

**Recipe (reusable across any topic):**
1. **Pick ONE everyday metaphor** and hold it consistently end-to-end (post office, kitchen, school, factory line). Map each component to one familiar object.
2. **Dual-label every node** (kid-word bound label + grey tech caption). Add one bottom "Kid word → real word" legend strip listing every mapping.
3. **Fixed colour grammar** so colour carries meaning: green = safe/go, red = stop/danger/escalate, yellow = careful/decision, blue = input/arrival, purple = trigger/schedule, orange = data/store/alert.
4. **Plain cause→effect arrow labels** ("pile not bigger → put back", "NO", "YES").
5. **`fontFamily:2`** (see Step 2 — never Virgil). Sketchy boxes (`roughness:1`) are welcome for the friendly feel.

**Dark theme (default for ELI5):** dark canvas (`appState.viewBackgroundColor:"#1f2428"`), LIGHT pastel node fills with DARK in-node text (high contrast), and LIGHT canvas-level text (title, grey captions ≈ `#adb5bd`, arrow labels). Never darken the node fills — light-text-on-dark-fill is where the "everything unreadable" bug lives. If the user prefers light, use a white canvas with dark text.

Centering is handled by the exporter — give each kid-word label a `containerId`; position the grey captions yourself just below each box.

## Maintenance notes (export pipeline)

`devflow visualizations render` → `lib/excalidraw-export.cjs` depends on three GLOBAL npm packages: `canvas`, `excalidraw-to-svg`, `@resvg/resvg-js`. If you touch this path:
- **node ≥ 25 requires `canvas@3+`** — `canvas@2` has no node-25 prebuilt (source build fails); `canvas@3.2.3+` ships a prebuilt binary.
- **`excalidraw-to-svg` reads `@excalidraw/utils` via a CWD-relative path** (`./node_modules/@excalidraw/utils/dist/excalidraw-utils.min.js`); with globally-installed deps the CLI passes `EXCAL_NODE_MODULES=$(npm root -g)` and the script `chdir`s to the dir whose `node_modules` holds it.
- **Global deps resolve via `NODE_PATH` — CommonJS `require` only, NOT ESM `import`** (this is why the script is `.cjs`).
- Don't suppress the `getContext` error — it signals a missing/misconfigured `canvas` (a real failure), unlike the cosmetic "Could not load img" jsdom warnings which are filtered.
- **Bound text is re-centered at export time** (`normalizeBoundText` in `excalidraw-export.cjs`): for every `text` with a `containerId`, the exporter overwrites x/y/width/height + `verticalAlign:middle` from the container box (horizontal via `text-anchor=middle`, vertical via `lines × fontSize × lineHeight`). This fixes hand-authored drift — classically multi-line labels riding the top edge. It re-positions only; it never grows boxes (warns instead) because growing would disconnect bound arrows. Empirically verified: `@excalidraw/utils` `exportToSvg` renders text at its LITERAL x/y and lays lines across the text element's own height — it does NOT live-recenter bound text the way the Excalidraw app does.
- **Background colour** comes from `appState.viewBackgroundColor` (or `--bg <color>`), not a hardcoded white — this is what lets dark-mode diagrams render on their dark canvas.
- **`fontFamily:2` only for rendered text** — resvg loads system fonts; Virgil (`fontFamily:1`) isn't one, so it falls back and text mis-renders.

$ARGUMENTS
