# Flow-separated marketplace + per-skill optional-deps — Design

- **Date:** 2026-06-12
- **Status:** Approved (brainstorming) — ready for `/devflow:spec-feature`
- **Branch:** `hardcore-raman-6c040e` (base v0.3.0)
- **Scope:** A (flow-separated plugins), B (per-skill requirements/optional-deps), C (move write-spike in), D (self-contained render), E (🟢🟡🔴 diagram-complexity rule)
- **Build order:** B → C → A → D → E (dependency-correct; flows generated in A must already carry B's manifests and C's write-spike). One MR at the end (merge ⇒ release).

## Problem

devflow ships as a single monolithic plugin (`devflow`, source `./` = `devflow-plugin/`). A user who only wants the code-review skills must install the entire pipeline (worktrees, phase-handoff, memory, observability). There is no way to install one flow standalone, no structured record of what each skill depends on, and no graceful handling when an optional dependency (e.g. Hindsight) is absent. Separately: `write-spike` lives in the wrong repo (`proof-of-skill`, symlinked), `devflow visualizations render` silently assumes its npm deps are pre-installed, and there is no in-product rule telling the agent when a diagram is complex enough to warrant a rendered Excalidraw.

## Goals

1. Install a **single flow** (e.g. just code review) without the full devflow structure, via normal `claude plugin install`.
2. Keep the existing full-devflow plugin working unchanged.
3. Every skill declares **REQUIRED + OPTIONAL** deps in a structured manifest that travels with a standalone single-skill install. **Hindsight is OPTIONAL everywhere.**
4. Missing OPTIONAL dep → ask the user (provide alternative / continue degraded / abort). No cross-repo deps.
5. `write-spike` becomes a real devflow skill (canonical home), not a symlink.
6. `devflow visualizations render` is self-contained — works with zero `devflow init`, auto-provisioning its npm deps.
7. A 🟢🟡🔴 diagram-complexity rule lives within devflow and reaches consuming projects.

## Non-Goals

- Cross-ecosystem (Codex / OpenCode) compat — explicitly a later, separate effort (scope F).
- Re-architecting the existing 3-copy skill convention (it stays; flows add a *generated* projection).
- A diagram-detection hook (rejected — see E).

---

## A — Flow-separated plugins, one marketplace

### Decision
Several small flow plugins **plus** the full plugin, all listed in the **existing** `devflow-plugin/.claude-plugin/marketplace.json`. One `marketplace add`; the user installs only the flow(s) they want. Each flow install has its own footprint and never drags in the pipeline.

### Marketplace entries

| Plugin | Source | Skills |
|---|---|---|
| `devflow` (unchanged) | `./` | all (full pipeline) |
| `devflow-review` | `./flows/review/` | review, review-document, write-spike |
| `devflow-diagrams` | `./flows/diagrams/` | render-diagram |
| `devflow-jira` | `./flows/jira/` | best-roi-task |

### Flow subtree layout
Each `flows/<flow>/` is a **self-contained mini-plugin**:

```
flows/review/
  .claude-plugin/plugin.json        # name devflow-review, version (bumped with repo), skills[] for this flow only
  commands/<skill>.md               # generated copy of devflow-plugin/commands/<skill>.md
  skills/<skill>/SKILL.md           # generated copy of devflow-plugin/skills/<skill>/SKILL.md
  skills/<skill>/requirements.json  # generated copy (B)
  skills/<skill>/<bundle files>     # render references/, write-spike templates, etc.
```

### Generation + drift guard
- Canonical source stays `devflow-plugin/{commands,skills}`. Flows are **generated**, never hand-edited.
- `scripts/build-flows.sh` (+ `make flows`) reads a flow→skills map and projects each subtree. The map lives in one place (e.g. `flows/flows.manifest` or a `case` in the script) so adding a skill to a flow is a one-line change.
- `make flows-check` regenerates to a temp dir and `git diff --exit-code`s against committed `flows/`; wired into `make test` and the finish-feature sensitive-file gate so a skill edit that forgets `make flows` fails loudly.
- Version bump (`bump_all_versions` in `lib/release.sh`) must also stamp the flow `plugin.json` files and the flow command badges (extend the existing globs).

### Open items for spec
- Confirm Claude Code requires a `.claude-plugin/plugin.json` per flow source dir (vs marketplace-entry metadata alone). Verify with one flow before generating all.
- Confirm `devflow` full plugin (`commands: "./commands/"`, explicit `skills[]`) does NOT also pick up `flows/**` (it points at `./commands/` non-recursively and an explicit `skills[]`, so it should not — verify).

---

## B — Per-skill `requirements.json` + prompt-driven preflight

### Manifest
Canonical `skills/<skill>/requirements.json`, mirrored to `devflow-plugin/skills/<skill>/requirements.json` and into the flow copies (by the generator). Schema:

```json
{
  "skill": "render-diagram",
  "required": [
    { "name": "node", "check": "node --version", "why": "runs the export pipeline", "install": "mise use -g node@latest" },
    { "name": "npm",  "check": "npm --version",  "why": "resolves render deps",     "install": "ships with node" }
  ],
  "optional": [
    { "name": "hindsight", "check": "recall reachable", "why": "recall prior diagram conventions", "install": "docker compose up hindsight", "degrade": "proceed without memory recall" }
  ]
}
```

Each dep: `name`, `check`, `why` (one line), `install` (hint), and for optional, `degrade` (what continuing-without means). **`check` is one of two forms:** a **shell command** (exit 0 ⇒ present, e.g. `node --version`), or a **named probe** the preflight knows how to run for non-command deps (e.g. `hindsight` ⇒ "is the Hindsight MCP/server reachable"). The preflight treats a non-shell-looking `check` as a named probe. Spec phase enumerates the supported named probes (initially just `hindsight`).

### Runtime check = prompt-driven preflight
A `## Preflight` block added to each SKILL.md (so a standalone single-skill install works with no devflow CLI present):

1. Read this skill's `requirements.json` (sibling file).
2. For each **required** dep: run its `check`. If any missing → STOP, report which + the `install` hint. Do not proceed.
3. For each **optional** dep missing → `AskUserQuestion`:
   - **Provide an alternative** (user supplies a path/command/endpoint),
   - **Continue without** (apply the dep's `degrade` behavior),
   - **Abort**.
4. Record the user's optional-dep choice for the rest of the run.

### Optional accelerator (full repo only)
`devflow deps check <skill>` CLI subcommand does steps 1–2 deterministically and prints a table. SKILL.md prefers the CLI when `devflow` is on PATH, else runs the check inline. The CLI is never *required* by a skill.

### Hindsight
Declared OPTIONAL on every skill that uses it (review, review-document, best-roi-task, render-diagram, write-spike, …). A single-skill install with no Hindsight running must work, degrading to "no recall / no retain".

### Mirror into registry.json
Add compact `requires` / `optional` name-lists per skill entry in `skills/registry.json` for full-repo discoverability (not the full schema — that lives in the per-skill file).

---

## C — Move write-spike into devflow

### Source → destination
From `~/.local/share/proof-of-skill/skills/write-spike/` (currently symlinked at `~/.claude/skills/write-spike`) into devflow as a full skill:

- `devflow-plugin/commands/write-spike.md` (add frontmatter + `[version]` badge)
- `devflow-plugin/skills/write-spike/{SKILL.md, spike-template.md, company-config.example.yaml, requirements.json}`
- `skills/write-spike/{…mirror…}` (3-copy)
- flow copy under `flows/review/` (generated)
- Register in `devflow-plugin/.claude-plugin/plugin.json` `skills[]` + `skills/registry.json` (category: `code-review`).

### Symlink + stale source
- Remove the `~/.claude/skills/write-spike` symlink so devflow is canonical.
- proof-of-skill source removal is a **follow-up in that repo** (out of scope here; flag it).

### Config handling (Aircall-specific)
- Ship `company-config.example.yaml` with placeholders.
- Skill resolves the real config from **`~/.config/devflow/write-spike/company-config.yaml`**, falling back to the bundled example. (NOT inside `~/dev/devflow` — honors the "never yadm-track under ~/dev" rule.)
- The real Aircall config is placed at that `$HOME` path and **YADM-tracked**.
- Result: review-document's `/devflow:write-spike` reference now resolves.

---

## D — Self-contained `devflow visualizations render`

### Dep self-provisioning (shared helper)
New `lib/render-deps.sh` resolves the 3 npm deps (`canvas`, `excalidraw-to-svg`, `@resvg/resvg-js`):

1. If existing globals (`npm root -g`) already have all three → use them (current behavior).
2. Else use a local cache `~/.devflow/render-deps/node_modules`.
3. If missing in both → `AskUserQuestion` consent, then `npm i --prefix ~/.devflow/render-deps canvas excalidraw-to-svg @resvg/resvg-js` (**local, no `-g`, no sudo**). Version-pinned (`canvas@3+` for node ≥ 25 per known gotcha).
4. Export `NODE_PATH` + `EXCAL_NODE_MODULES` pointing at whichever dir won.

`viz_render` calls this helper instead of dying with a hint. Works with zero `devflow init` (already true for path resolution; this closes the deps gap).

### Standalone diagrams flow (no `bin/devflow` on PATH)
The `devflow-diagrams` flow bundles `excalidraw-export.cjs` + `render-deps.sh` + a tiny launcher so render-diagram renders without the full CLI. render-diagram's render step:
- If `devflow` is on PATH → `devflow visualizations render …` (existing path).
- Else → `node "$SKILL_DIR/excalidraw-export.cjs" …` with deps resolved by the bundled `render-deps.sh`.

`node` + `npm` are REQUIRED in render-diagram's `requirements.json` so preflight catches their absence cleanly.

### Open item for spec
Avoid divergence between the CLI path and the standalone path — both source the same `render-deps.sh` logic (bundled into the flow, canonical in `lib/`).

---

## E — 🟢🟡🔴 diagram-complexity rule

### Rule text (~6 lines, canonical)
> **Before drawing any diagram, rate its complexity:**
> - 🟢 **simple** — linear / ≤4 nodes → plain ASCII is fine, no render needed.
> - 🟡 **moderate** — fork-join, 5–8 nodes, or one crossing → **OFFER** a rendered Excalidraw via `/devflow:render-diagram`.
> - 🔴 **complex** — bidirectional, multi-lane, >8 nodes, or cycles → render via `/devflow:render-diagram` **and SHOW it inline** via the Read tool.

### Delivery (context injection, no hook)
1. Add the rule to `templates/CLAUDE.md.tmpl` so newly `devflow init`'d projects get it.
2. `devflow init` injects it into the consuming project's CLAUDE.md inside the devflow-managed marker block (exact target — project vs global `~/.claude/CLAUDE.md` block — confirmed at spec time; lean project-level so it travels with the repo).
3. Embed the rule at the **top** of render-diagram + the diagram-producing skills (spec-feature, codebase-walkthrough, update-visualizations, architecture-decision) so it fires even where `devflow init` was never run.

### Why not a hook
A `UserPromptSubmit` hook would regex diagram keywords, but (a) keyword detection is fuzzy and (b) the model usually decides to draw *mid-task* with no "draw" keyword in the user's prompt — so the hook fires at the wrong moment and misses model-initiated diagrams. Always-on context injection fires exactly when the model is about to draw. (Noted: `devflow init` *can* write project-scoped hooks into a project's `.claude/settings.json`; this rule simply doesn't need one.)

---

## Build sequence (one MR, staged commits)

1. **B** — `requirements.json` schema + per-skill files for the in-scope skills + the `## Preflight` block + optional `devflow deps check` CLI + registry mirror.
2. **C** — move write-spike in (3-copy + register + config split + remove symlink).
3. **A** — `flows/` generator (`scripts/build-flows.sh`, `make flows`, `make flows-check`) + 3 flow mini-plugins + marketplace.json entries + release version-stamping of flow files.
4. **D** — `lib/render-deps.sh` + `viz_render` integration + diagrams-flow bundling for standalone render.
5. **E** — rule text into template + init injection + skill embedding.

Each step is its own conventional commit. MR opens only after E lands (merge ⇒ release; never write the literal skip-release marker in commit prose).

## Risks / things to verify during spec

- Per-flow `plugin.json` requirement + non-recursion of the full plugin's `commands` dir (A).
- `devflow init` CLAUDE.md injection target + idempotency for the rule block (E).
- bash 3.2 safety in `render-deps.sh` and `build-flows.sh` (empty-array idiom, `grep -c` pipefail) — known macOS gotchas.
- Generator must keep flow copies byte-identical to canonical (extends the 3-copy rule to a generated 4th copy; `make flows-check` enforces).
- `npm i --prefix` cache path interaction with `excalidraw-to-svg`'s CWD-relative `@excalidraw/utils` load (set `EXCAL_NODE_MODULES` correctly).

## Testing approach

- Bats unit tests: `_parse`/version-stamp extension for flow files, `build-flows` produces expected tree, `flows-check` detects drift, `render-deps` resolution order (globals → cache → install-consent).
- Manifest/preflight: a fixture skill with a known-missing optional dep; assert the AskUserQuestion path.
- Manual: install `devflow-review` alone in a throwaway project, confirm no pipeline skills present + review runs; render a 🔴 diagram with only the `devflow-diagrams` flow installed (no `bin/devflow`).
