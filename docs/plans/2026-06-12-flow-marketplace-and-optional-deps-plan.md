# Flow-separated marketplace + per-skill optional-deps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users install a single devflow *flow* (review / diagrams / jira) standalone via the existing marketplace, give every skill a structured required/optional dependency manifest with a prompt-driven preflight (Hindsight optional), move write-spike into devflow, make `devflow visualizations render` self-provision its npm deps, and ship a 🟢🟡🔴 diagram-complexity rule — all in one MR (merge ⇒ release).

**Architecture:** Canonical skills stay 3-copy (`devflow-plugin/commands/<n>.md`, `devflow-plugin/skills/<n>/`, `skills/<n>/`). A generator (`scripts/build-flows.sh`, driven by `scripts/flows.manifest`) projects per-flow mini-plugins into `devflow-plugin/flows/<flow>/` (each with its own `.claude-plugin/plugin.json`), registered as extra entries in the existing `devflow-plugin/.claude-plugin/marketplace.json`. Flows are a *generated 4th copy* — never hand-edited; `make flows-check` guards drift. Per-skill `requirements.json` + a reusable `## Preflight` block drive optional-dep handling. `lib/render-deps.sh` resolves npm deps (globals → `~/.devflow/render-deps` cache → consent install).

**Tech Stack:** Bash (`/bin/bash` 3.2-safe), Bats + `tests/helpers/{mocks,assertions,common}.bash`, Node ≥25 + `canvas@3+`/`excalidraw-to-svg`/`@resvg/resvg-js`, Claude Code plugin marketplace, jq.

**Build order:** B → C → A → D → E → finish. One MR, conventional commits, opened only after E lands. Never write the literal skip-release marker in commit prose.

---

## Resolved design questions (authoritative — from claude-code-guide + code read)

- **Plugin discovery is NOT whole-tree recursive.** Default roots: `skills/`, `commands/`, root `SKILL.md`. A skill at `devflow-plugin/flows/<flow>/skills/<n>/SKILL.md` is invisible to the full `devflow` plugin (rooted at `devflow-plugin/`) because `flows/` is not a discovery root. → **Flows live at `devflow-plugin/flows/<flow>/`. No double-discovery.**
- **`source` resolves relative to the marketplace root** (dir containing `.claude-plugin/`) = `devflow-plugin/`. `../` is forbidden. → flow source = `./flows/<flow>`.
- **Each flow gets its own `.claude-plugin/plugin.json`** (`name: devflow-<flow>`, version synced).
- **Namespacing:** full-plugin skills are `/devflow:<n>`; flow skills are `/devflow-<flow>:<n>`. → review-document references write-spike **namespace-agnostically** (prose "the write-spike skill", not a hardcoded `/devflow:` slash).
- **init CLAUDE.md** currently appends `templates/CLAUDE.md.tmpl` only if `<!-- devflow -->` absent → existing installs never get template updates. Template already carries both `<!-- devflow -->` and `<!-- /devflow -->`. → add a marker-block *replace* path so re-init refreshes; skill-embedding covers everyone regardless.
- **flows.manifest** = pipe-delimited `scripts/flows.manifest` (bash-3.2-safe, no assoc arrays).
- **npm mock** = branching stub on `$1` (`root -g` vs `install`), via the `mock_cmd` PATH-prepend pattern.

## File Structure (created / modified)

**Created**
- `scripts/flows.manifest` — flow→skills map
- `scripts/build-flows.sh` — generator
- `lib/deps.sh` — `devflow deps check <skill>` (preflight accelerator)
- `lib/render-deps.sh` — npm dep resolver (shared by CLI + standalone flow)
- `skills/<n>/requirements.json` + `devflow-plugin/skills/<n>/requirements.json` — per skill (review, review-document, best-roi-task, render-diagram, write-spike)
- `devflow-plugin/commands/write-spike.md`, `devflow-plugin/skills/write-spike/{SKILL.md,spike-template.md,company-config.example.yaml,requirements.json}`, `skills/write-spike/{…}`
- `devflow-plugin/flows/<flow>/…` — GENERATED (do not hand-edit)
- `tests/unit/{flows,render-deps,deps,requirements}.bats`

**Modified**
- `devflow-plugin/.claude-plugin/marketplace.json` — +3 plugin entries
- `bin/devflow` — `deps)` + `flows)` case arms + help
- `lib/release.sh` `bump_all_versions` — stamp flow `plugin.json` + flow command badges
- `lib/visualizations.sh` `viz_render` — use `lib/render-deps.sh`
- `lib/init.sh` — marker-block replace helper for the devflow CLAUDE.md block
- `templates/CLAUDE.md.tmpl` — add the 🟢🟡🔴 rule inside the block
- `Makefile` — `flows`, `flows-check` targets; `test` depends on `flows-check`
- `skills/registry.json` — write-spike entry + compact `requires`/`optional` per skill
- SKILL.md (3-copy) for review, review-document, best-roi-task, render-diagram, write-spike — add `## Preflight`
- render-diagram + spec-feature + codebase-walkthrough + update-visualizations + architecture-decision SKILL.md (3-copy) — embed the rule
- `lib/finish-feature` sensitive gate — include `flows-check`

**Standard step cadence** (applies to every implementation task): (1) write failing test, (2) run it — confirm FAIL, (3) implement, (4) run — confirm PASS, (5) `make test-unit` + commit. Code blocks below give the actual test + impl content per task.

---

# Phase B — requirements.json + preflight

### Task B1: requirements.json schema + per-skill files

**Files:**
- Create: `skills/render-diagram/requirements.json`, `skills/review/requirements.json`, `skills/review-document/requirements.json`, `skills/best-roi-task/requirements.json` (+ `devflow-plugin/skills/<n>/requirements.json` mirrors)
- Test: `tests/unit/requirements.bats`

- [ ] **Step 1 — write failing test** (`tests/unit/requirements.bats`):

```bash
#!/usr/bin/env bats
load '../helpers/common'
load '../helpers/assertions'

setup() { REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"; }

@test "every in-scope skill has a valid requirements.json with skill/required/optional keys" {
  for s in render-diagram review review-document best-roi-task; do
    local f="${REPO}/skills/${s}/requirements.json"
    assert [ -f "$f" ]
    run jq -e '.skill and (.required|type=="array") and (.optional|type=="array")' "$f"
    assert_success
  done
}

@test "hindsight is declared OPTIONAL (never required) wherever it appears" {
  for f in "${REPO}"/skills/*/requirements.json; do
    run jq -e '[.required[]?.name] | index("hindsight")' "$f"
    assert_failure   # hindsight must NOT be in required[]
  done
}

@test "render-diagram requires node and npm" {
  run jq -e '[.required[].name] | (index("node") and index("npm"))' "${REPO}/skills/render-diagram/requirements.json"
  assert_success
}

@test "each dep has name, check, why" {
  for f in "${REPO}"/skills/*/requirements.json; do
    run jq -e '[.required[],.optional[]] | all(has("name") and has("check") and has("why"))' "$f"
    assert_success
  done
}
```

- [ ] **Step 2 — run, confirm FAIL** — `make test-unit` (or `bats tests/unit/requirements.bats`); expect FAIL (files absent).

- [ ] **Step 3 — create `skills/render-diagram/requirements.json`:**

```json
{
  "skill": "render-diagram",
  "required": [
    { "name": "node", "check": "node --version", "why": "runs the pure-node export pipeline", "install": "mise use -g node@latest (or any Node ≥25)" },
    { "name": "npm", "check": "npm --version", "why": "resolves/installs the render deps", "install": "ships with Node" }
  ],
  "optional": [
    { "name": "devflow-cli", "check": "command -v devflow", "why": "convenience wrapper `devflow visualizations render`", "install": "make install (devflow repo)", "degrade": "call node on the bundled excalidraw-export.cjs directly" },
    { "name": "hindsight", "check": "hindsight", "why": "recall prior diagram conventions for this repo", "install": "docker compose up -d hindsight", "degrade": "proceed without recall" }
  ]
}
```

- [ ] **Step 4 — create the other three** (same shape). `review` / `review-document`: required `git`; optional `gh`/`glab` (degrade: skip remote-MR fetch, review local diff), `hindsight` (degrade: no recall). `best-roi-task`: required `none` (empty `required: []`); optional Atlassian access (`atlassian`, degrade: ask user to paste the epic), `hindsight`. Write each + its `devflow-plugin/skills/<n>/` mirror (byte-identical).

- [ ] **Step 5 — run, confirm PASS; `make test-unit`; commit:**

```bash
git add skills/*/requirements.json devflow-plugin/skills/*/requirements.json tests/unit/requirements.bats
git commit -m "feat(deps): add per-skill requirements.json (required+optional, hindsight optional)" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task B2: reusable `## Preflight` block in each SKILL.md

**Files:** Modify (3-copy each): `{devflow-plugin/skills,skills}/<n>/SKILL.md` + `devflow-plugin/commands/<n>.md` for render-diagram, review, review-document, best-roi-task. No new test (prose). Verified by B4's `deps check` + manual.

- [ ] **Step 1 — define the canonical block** (paste verbatim near the top of each SKILL.md, after the title):

```markdown
## Preflight (dependency check)

Before doing the skill's work, resolve dependencies from the sibling `requirements.json`:

1. Read `requirements.json` next to this SKILL.md. If absent, skip preflight (no declared deps).
2. If `devflow` is on PATH, run `devflow deps check <skill-name>` and use its report. Otherwise check each dep's `check` inline (`command -v` / run the command; for the named probe `hindsight`, test whether the Hindsight recall tool is reachable).
3. **Required dep missing** → STOP. Report the dep `name`, `why`, and `install` hint. Do not continue.
4. **Optional dep missing** → ask via `AskUserQuestion` (header "Optional dep"): **Provide an alternative** (user supplies a path/command/endpoint) · **Continue without** (apply the dep's `degrade` behavior) · **Abort**. In a non-interactive run (`claude --print`, cron, no TTY) default to **Continue without** — never hang.
5. Carry the chosen optional-dep behavior through the rest of the run.
```

- [ ] **Step 2 — insert into all 4 skills' 3 copies** (12 SKILL-side edits + keep command `.md` bodies byte-identical to their SKILL.md per the 3-copy rule). For best-roi-task whose `required` is empty, the block still applies (only optional prompts fire).

- [ ] **Step 3 — verify byte-identity** of the three copies per skill:

```bash
for s in render-diagram review review-document best-roi-task; do
  diff <(sed '1,/^---$/d;/^---$/,$d' /dev/null) /dev/null 2>/dev/null
  diff "devflow-plugin/skills/$s/SKILL.md" "skills/$s/SKILL.md" && echo "$s: skill copies match"
done
```

- [ ] **Step 4 — commit:**

```bash
git add devflow-plugin/skills/*/SKILL.md skills/*/SKILL.md devflow-plugin/commands/*.md
git commit -m "feat(deps): add Preflight block to in-scope skills (optional-dep handling)" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task B3: `devflow deps check <skill>` accelerator

**Files:** Create `lib/deps.sh`; Modify `bin/devflow` (source + case arm + help); Test `tests/unit/deps.bats`.

- [ ] **Step 1 — failing test** (`tests/unit/deps.bats`):

```bash
#!/usr/bin/env bats
load '../helpers/common'; load '../helpers/assertions'; load '../helpers/mocks'
setup() { REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"; }

@test "deps check reports OK when all required present" {
  run "${REPO}/bin/devflow" deps check render-diagram
  assert_success
  assert_output --partial "render-diagram"
}

@test "deps check exits non-zero and names the dep when a required dep is missing" {
  # shim that hides node by overriding command resolution is hard; instead test the
  # parser against a fixture with an impossible required check.
  local tmp="${BATS_TEST_TMPDIR}/req.json"
  printf '{"skill":"x","required":[{"name":"definitely_absent_bin_xyz","check":"definitely_absent_bin_xyz --v","why":"w","install":"i"}],"optional":[]}' > "$tmp"
  run "${REPO}/bin/devflow" deps check --file "$tmp"
  assert_failure
  assert_output --partial "definitely_absent_bin_xyz"
}
```

- [ ] **Step 2 — run, confirm FAIL.**

- [ ] **Step 3 — create `lib/deps.sh`:**

```bash
#!/usr/bin/env bash
# lib/deps.sh — devflow deps check <skill> : report required/optional dep status.

# _deps_resolve_file <skill-or-flag-args...> -> echoes path to requirements.json
_deps_resolve_file() {
  if [[ "${1:-}" == "--file" ]]; then echo "${2:-}"; return 0; fi
  local skill="${1:?usage: devflow deps check <skill>|--file <path>}"
  local root; root="$(devflow_root)"
  for c in "${root}/devflow-plugin/skills/${skill}/requirements.json" "${root}/skills/${skill}/requirements.json"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

# _deps_check_one <check-string> -> 0 present, 1 missing
_deps_check_one() {
  local check="$1"
  case "$check" in
    hindsight) [[ -n "${HINDSIGHT_URL:-}" ]] || command -v uvx >/dev/null 2>&1 ;;  # named probe (best-effort)
    *) eval "$check" >/dev/null 2>&1 ;;
  esac
}

devflow_deps() {
  local sub="${1:-}"; shift || true
  [[ "$sub" == "check" ]] || die "Usage: devflow deps check <skill>"
  local file; file="$(_deps_resolve_file "$@")" || die "No requirements.json for: ${1:-<skill>}"
  has_cmd jq || die "jq required for deps check"
  local skill; skill="$(jq -r '.skill // "?"' "$file")"
  section "deps: ${skill}"
  local missing_required=0 n why inst chk
  while IFS=$'\t' read -r n chk why inst; do
    if _deps_check_one "$chk"; then ok "required ${n}"; else status_fail "required ${n} — ${why} (install: ${inst})"; missing_required=1; fi
  done < <(jq -r '.required[]? | [.name,.check,.why,(.install//"")] | @tsv' "$file")
  while IFS=$'\t' read -r n chk why inst; do
    if _deps_check_one "$chk"; then ok "optional ${n}"; else warn "optional ${n} missing — ${why}"; fi
  done < <(jq -r '.optional[]? | [.name,.check,.why,(.install//"")] | @tsv' "$file")
  [[ "$missing_required" -eq 0 ]] || return 1
  return 0
}
```

- [ ] **Step 4 — wire into `bin/devflow`** (source near other libs; add arm in the dispatch case + a help line):

```bash
# in the lib-source block:
source "${DEVFLOW_LIB}/deps.sh"
# in the case dispatch (near skills/check-version):
    deps)      devflow_deps "$@" ;;
```

- [ ] **Step 5 — run, confirm PASS; commit:**

```bash
git add lib/deps.sh bin/devflow tests/unit/deps.bats
git commit -m "feat(deps): add 'devflow deps check <skill>' accelerator" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task B4: mirror compact requires/optional into registry.json

**Files:** Modify `skills/registry.json`. Test: extend `tests/unit/requirements.bats`.

- [ ] **Step 1 — failing test** (append to requirements.bats):

```bash
@test "registry mirrors requires/optional name-lists for in-scope skills" {
  for s in render-diagram review review-document best-roi-task; do
    run jq -e --arg s "$s" '.skills[] | select(.name==$s) | (.requires|type=="array") and (.optional|type=="array")' "${REPO}/skills/registry.json"
    assert_success
  done
}
```

- [ ] **Step 2 — run FAIL → Step 3 — add `"requires": [...]`, `"optional": [...]` name-lists** to each in-scope skill entry in `registry.json` (compact: just names, matching the per-skill files). **Step 4 — run PASS; commit:**

```bash
git add skills/registry.json tests/unit/requirements.bats
git commit -m "feat(deps): mirror requires/optional name-lists into registry.json" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

# Phase C — move write-spike into devflow

### Task C1: bring write-spike in as a 3-copy skill

**Files:** Create `devflow-plugin/commands/write-spike.md`, `devflow-plugin/skills/write-spike/{SKILL.md,spike-template.md,company-config.example.yaml,requirements.json}`, `skills/write-spike/{…mirror…}`. Modify `devflow-plugin/.claude-plugin/plugin.json` (skills[]), `skills/registry.json`. Test: `tests/unit/requirements.bats` already covers requirements.json presence once added to the loop.

- [ ] **Step 1 — copy source content:**

```bash
SRC="$HOME/.local/share/proof-of-skill/skills/write-spike"
mkdir -p devflow-plugin/skills/write-spike skills/write-spike
cp "$SRC/SKILL.md"          devflow-plugin/skills/write-spike/SKILL.md
cp "$SRC/spike-template.md" devflow-plugin/skills/write-spike/spike-template.md
cp "$SRC/company-config.yaml" devflow-plugin/skills/write-spike/company-config.example.yaml   # becomes the EXAMPLE
```

- [ ] **Step 2 — genericize `company-config.example.yaml`** — replace any Aircall-specific values with placeholders (`project_tracker: jira`, `default_spike_location: ~/docs/spikes`, etc. are already generic; scrub any company/line IDs if present).

- [ ] **Step 3 — edit `devflow-plugin/skills/write-spike/SKILL.md`** — change the "Company Configuration" section to resolve config in this order and reference the example, namespace-agnostic write-spike reference:

```markdown
## Company Configuration

Resolve config (first that exists):
1. `~/.config/devflow/write-spike/company-config.yaml`  (your real config — keep it out of any repo; YADM-track it)
2. `company-config.example.yaml` in this skill dir (placeholders / defaults)

If neither exists, ask the user for the minimum (project tracker, chat platform, VCS provider).
```

- [ ] **Step 4 — create `devflow-plugin/commands/write-spike.md`** — frontmatter + version badge + body byte-identical to SKILL.md:

```markdown
---
description: [0.3.0] Use when starting a new initiative spike, investigating technical feasibility, assessing impact across services, or writing an engineering discovery document — produces a structured spike doc with diagrams and a private notes file.
---

<body byte-identical to devflow-plugin/skills/write-spike/SKILL.md>
```

- [ ] **Step 5 — create `devflow-plugin/skills/write-spike/requirements.json`:**

```json
{
  "skill": "write-spike",
  "required": [],
  "optional": [
    { "name": "atlassian", "check": "atlassian", "why": "fetch the Jira ticket + Confluence context", "install": "connect the Atlassian MCP", "degrade": "ask the user to paste ticket text" },
    { "name": "slack", "check": "slack", "why": "pull chat context for the initiative", "install": "connect the Slack MCP", "degrade": "skip chat context" },
    { "name": "hindsight", "check": "hindsight", "why": "recall prior initiative learnings", "install": "docker compose up -d hindsight", "degrade": "proceed without recall" }
  ]
}
```

- [ ] **Step 6 — add the `## Preflight` block** (from B2) to write-spike SKILL.md (both copies) + the command body.

- [ ] **Step 7 — mirror into `skills/write-spike/`** (SKILL.md, spike-template.md, company-config.example.yaml, requirements.json — byte-identical).

- [ ] **Step 8 — register** in `devflow-plugin/.claude-plugin/plugin.json` `skills[]` (`"./skills/write-spike/SKILL.md"`) and `skills/registry.json` (new entry, category `code-review`, requires `[]`, optional `["atlassian","slack","hindsight"]`).

- [ ] **Step 9 — run `make test-unit`; commit:**

```bash
git add devflow-plugin/commands/write-spike.md devflow-plugin/skills/write-spike skills/write-spike devflow-plugin/.claude-plugin/plugin.json skills/registry.json
git commit -m "feat(write-spike): move write-spike into devflow as a first-class skill" \
  -m "Real files brought in from proof-of-skill (was symlinked by mistake). Config split: company-config.example.yaml committed; real config resolves from ~/.config/devflow/write-spike/company-config.yaml." \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task C2: real config to ~/.config + YADM; remove symlink; fix review-document reference

**Files:** filesystem (`~/.config/devflow/write-spike/`, `~/.claude/skills/write-spike` symlink), `devflow-plugin/commands/review-document.md` + `{devflow-plugin/skills,skills}/review-document/SKILL.md`.

- [ ] **Step 1 — place real config + YADM-track** (outside any ~/dev repo):

```bash
mkdir -p ~/.config/devflow/write-spike
cp "$HOME/.local/share/proof-of-skill/skills/write-spike/company-config.yaml" ~/.config/devflow/write-spike/company-config.yaml
yadm add ~/.config/devflow/write-spike/company-config.yaml
yadm commit -m "add write-spike company config (real, Aircall)"
```

- [ ] **Step 2 — remove the stale symlink** so devflow is canonical:

```bash
[ -L ~/.claude/skills/write-spike ] && rm ~/.claude/skills/write-spike && echo "removed symlink"
```

- [ ] **Step 3 — fix review-document's write-spike reference** — replace any hardcoded `/devflow:write-spike` with namespace-agnostic prose: "its authoring counterpart, the **write-spike** skill (`/devflow:write-spike` in the full plugin, `/devflow-review:write-spike` in the review flow)". Apply to all 3 copies (byte-identical body).

- [ ] **Step 4 — verify + commit** (repo changes only; the ~/.config + symlink are local/YADM):

```bash
grep -rn "write-spike" devflow-plugin/skills/review-document/SKILL.md
git add devflow-plugin/commands/review-document.md devflow-plugin/skills/review-document/SKILL.md skills/review-document/SKILL.md
git commit -m "fix(review-document): reference write-spike namespace-agnostically" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

# Phase A — flow plugins (generator + marketplace)

### Task A1: flows.manifest + build-flows.sh (verify on ONE flow first)

**Files:** Create `scripts/flows.manifest`, `scripts/build-flows.sh`. Test `tests/unit/flows.bats`.

- [ ] **Step 1 — create `scripts/flows.manifest`** (pipe-delimited; bash-3.2-safe):

```
# flow|comma-separated skills   (canonical source = devflow-plugin/{commands,skills})
review|review,review-document,write-spike
diagrams|render-diagram
jira|best-roi-task
```

- [ ] **Step 2 — failing test** (`tests/unit/flows.bats`):

```bash
#!/usr/bin/env bats
load '../helpers/common'; load '../helpers/assertions'
setup() { REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"; }

@test "build-flows generates each flow as a self-contained mini-plugin" {
  run bash "${REPO}/scripts/build-flows.sh"
  assert_success
  for fl in review diagrams jira; do
    assert [ -f "${REPO}/devflow-plugin/flows/${fl}/.claude-plugin/plugin.json" ]
  done
  assert [ -f "${REPO}/devflow-plugin/flows/review/skills/write-spike/SKILL.md" ]
  assert [ -f "${REPO}/devflow-plugin/flows/review/skills/write-spike/requirements.json" ]
  assert [ -f "${REPO}/devflow-plugin/flows/diagrams/skills/render-diagram/SKILL.md" ]
}

@test "flow plugin.json name is devflow-<flow> and version matches the full plugin" {
  bash "${REPO}/scripts/build-flows.sh" >/dev/null
  local v; v="$(jq -r .version "${REPO}/devflow-plugin/.claude-plugin/plugin.json")"
  run jq -r .name "${REPO}/devflow-plugin/flows/review/.claude-plugin/plugin.json"
  assert_output "devflow-review"
  run jq -r .version "${REPO}/devflow-plugin/flows/review/.claude-plugin/plugin.json"
  assert_output "$v"
}

@test "flow copies are byte-identical to canonical skill SKILL.md" {
  bash "${REPO}/scripts/build-flows.sh" >/dev/null
  run diff "${REPO}/devflow-plugin/skills/render-diagram/SKILL.md" "${REPO}/devflow-plugin/flows/diagrams/skills/render-diagram/SKILL.md"
  assert_success
}
```

- [ ] **Step 3 — run FAIL → create `scripts/build-flows.sh`:**

```bash
#!/usr/bin/env bash
# scripts/build-flows.sh — generate per-flow mini-plugins from canonical sources.
# Flows are a GENERATED 4th copy; never hand-edit devflow-plugin/flows/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="${ROOT}/devflow-plugin"
MANIFEST="${ROOT}/scripts/flows.manifest"
VERSION="$(jq -r .version "${PLUGIN}/.claude-plugin/plugin.json")"

[[ -f "$MANIFEST" ]] || { echo "missing $MANIFEST" >&2; exit 1; }

while IFS='|' read -r flow skills || [[ -n "$flow" ]]; do   # `|| [[ -n ]]` keeps the last line if no trailing newline
  case "$flow" in ''|\#*) continue ;; esac
  flow="$(echo "$flow" | tr -d '[:space:]')"
  outdir="${PLUGIN}/flows/${flow}"
  rm -rf "$outdir"
  mkdir -p "${outdir}/.claude-plugin" "${outdir}/commands" "${outdir}/skills"
  # per-flow plugin.json
  printf '{\n  "name": "devflow-%s",\n  "description": "devflow %s flow",\n  "version": "%s",\n  "author": { "name": "Andre Jorge Lopes" },\n  "commands": "./commands/"\n}\n' \
    "$flow" "$flow" "$VERSION" > "${outdir}/.claude-plugin/plugin.json"
  # copy each skill (command + skill dir incl. bundle files)
  local_skills="$(echo "$skills" | tr ',' ' ')"
  for sk in $local_skills; do
    sk="$(echo "$sk" | tr -d '[:space:]')"
    [[ -d "${PLUGIN}/skills/${sk}" ]] || { echo "unknown skill '$sk' in flow '$flow'" >&2; exit 1; }
    cp "${PLUGIN}/commands/${sk}.md" "${outdir}/commands/${sk}.md"
    cp -R "${PLUGIN}/skills/${sk}" "${outdir}/skills/${sk}"
  done
  echo "built flow: ${flow} (${skills})"
done < "$MANIFEST"
```

> Note: `local` at top level is harmless in bash; if shellcheck objects, drop the keyword (loop body is not a function). Keep `set -euo pipefail`; the `for sk in $local_skills` word-split is intentional and bash-3.2-safe (no arrays).

- [ ] **Step 4 — VERIFY on ONE flow before trusting all** (manual gate per the resolved-questions note):

```bash
bash scripts/build-flows.sh
claude plugin validate devflow-plugin 2>&1 | tail -20 || true   # structure check
# Confirm the full plugin does NOT list flow skills (namespacing sanity):
jq -r '.skills[]' devflow-plugin/.claude-plugin/plugin.json | grep -c flows/ || echo "0 flow refs in full plugin (correct)"
```

- [ ] **Step 5 — run PASS; commit:**

```bash
git add scripts/flows.manifest scripts/build-flows.sh tests/unit/flows.bats devflow-plugin/flows
git commit -m "feat(flows): generator + flows.manifest + generated flow mini-plugins" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A2: Makefile flows/flows-check + drift guard

**Files:** Modify `Makefile`; Modify `lib/finish-feature` (sensitive gate). Test: extend `tests/unit/flows.bats`.

- [ ] **Step 1 — failing test** (append to flows.bats):

```bash
@test "flows-check fails when a canonical skill changed but flows were not regenerated" {
  # Work on a committed COPY so the diff baseline is clean and the real repo is untouched.
  local work="${BATS_TEST_TMPDIR}/repo"; cp -R "${REPO}" "$work"
  ( cd "$work" && git add -A && git -c user.email=t -c user.name=t commit -q -m snapshot )
  # Tamper the CANONICAL source (uncommitted). flows-check's first action is build-flows.sh,
  # which regenerates the flow copy FROM the tampered canonical -> working-tree flow now
  # differs from the committed flow -> `git diff -- flows` is dirty -> flows-check exits 1.
  # (Tampering the generated copy instead would be wiped by build-flows' rm -rf before the diff.)
  printf '\n<!-- drift -->\n' >> "$work/devflow-plugin/skills/render-diagram/SKILL.md"
  run make -C "$work" flows-check
  assert_failure
}
```

- [ ] **Step 2 — run FAIL → add Makefile targets:**

```make
flows: ## Regenerate flow mini-plugins from canonical sources
	@bash scripts/build-flows.sh

flows-check: ## Fail if generated flows drift from canonical sources
	@bash scripts/build-flows.sh
	@git diff --quiet -- devflow-plugin/flows || { echo "flows out of date — run 'make flows' and commit"; git --no-pager diff --stat -- devflow-plugin/flows; exit 1; }
```

And make `test` depend on `flows-check` (prepend to the `test:` recipe or its prereqs).

- [ ] **Step 3 — wire into finish-feature sensitive gate** — add a `flows-check` invocation to `lib/finish-feature` pre-PR checks (so a finish never ships drifted flows).

- [ ] **Step 4 — run PASS; commit:**

```bash
git add Makefile lib/finish-feature tests/unit/flows.bats
git commit -m "feat(flows): make flows/flows-check targets + drift guard in test + finish" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A3: marketplace entries + release version-stamping of flows

**Files:** Modify `devflow-plugin/.claude-plugin/marketplace.json`, `lib/release.sh` (`bump_all_versions`). Test `tests/unit/release.bats` (extend).

- [ ] **Step 1 — add the 3 plugin entries** to `marketplace.json` `plugins[]`:

```json
{ "name": "devflow-review",   "description": "devflow code-review flow (review, review-document, write-spike)", "source": "./flows/review",   "version": "0.3.0" },
{ "name": "devflow-diagrams", "description": "devflow diagram flow (render-diagram)",                            "source": "./flows/diagrams", "version": "0.3.0" },
{ "name": "devflow-jira",     "description": "devflow jira flow (best-roi-task)",                                 "source": "./flows/jira",     "version": "0.3.0" }
```

- [ ] **Step 2 — failing test** (append to release.bats):

```bash
@test "bump_all_versions stamps flow plugin.json files" {
  bash "${REPO}/scripts/build-flows.sh" >/dev/null
  source "${REPO}/lib/utils.sh"; source "${REPO}/lib/watch.sh"; source "${REPO}/lib/release.sh"
  local work="${BATS_TEST_TMPDIR}/repo"; cp -R "${REPO}" "$work"
  bump_all_versions "9.9.9" "$work" >/dev/null
  run jq -r .version "$work/devflow-plugin/flows/review/.claude-plugin/plugin.json"
  assert_output "9.9.9"
}
```

- [ ] **Step 3 — run FAIL → extend `bump_all_versions`** (in `lib/release.sh`) after the existing plugin/marketplace stamps:

```bash
  # Flow mini-plugin plugin.json files (generated)
  local flow_pj
  for flow_pj in "$proj"/devflow-plugin/flows/*/.claude-plugin/plugin.json; do
    [[ -f "$flow_pj" ]] || continue
    _sed_inplace "s/\"version\": \"[^\"]*\"/\"version\": \"${new_version}\"/" "$flow_pj"
  done
  # Flow command badges
  for cmd_file in "$proj"/devflow-plugin/flows/*/commands/*.md; do
    [[ -f "$cmd_file" ]] || continue
    _sed_inplace "s/^description: \[[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\] /description: [${new_version}] /" "$cmd_file"
  done
```

> Order: ensure `bump_all_versions` (or the release flow) runs `build-flows.sh` BEFORE stamping, OR stamps then the next `make flows` regenerates from the already-stamped canonical. Simplest: regen flows first (full plugin badge already bumped), then stamp flow files. Document in the release runbook.

- [ ] **Step 4 — run PASS; commit:**

```bash
git add devflow-plugin/.claude-plugin/marketplace.json lib/release.sh tests/unit/release.bats devflow-plugin/flows
git commit -m "feat(flows): register flow plugins in marketplace + stamp flow versions on bump" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

# Phase D — self-contained render

### Task D1: lib/render-deps.sh + viz_render integration

**Files:** Create `lib/render-deps.sh`; Modify `lib/visualizations.sh` (`viz_render`), `bin/devflow` (source render-deps). Test `tests/unit/render-deps.bats`.

- [ ] **Step 1 — failing test** (`tests/unit/render-deps.bats`) using a branching npm stub:

```bash
#!/usr/bin/env bats
load '../helpers/common'; load '../helpers/assertions'
setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  MOCK="${BATS_TEST_TMPDIR}/bin"; mkdir -p "$MOCK"
  # branching npm stub: 'root -g' -> empty dir (no deps); 'install --prefix DIR ...' -> create node_modules/<pkgs>
  cat > "$MOCK/npm" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "root" ] && [ "$2" = "-g" ]; then echo "/nonexistent-global-root"; exit 0; fi
if [ "$1" = "install" ] || [ "$1" = "i" ]; then
  pfx=""; while [ $# -gt 0 ]; do [ "$1" = "--prefix" ] && { pfx="$2"; shift; }; shift; done
  mkdir -p "$pfx/node_modules/canvas" "$pfx/node_modules/excalidraw-to-svg" "$pfx/node_modules/@resvg/resvg-js"; exit 0
fi
exit 0
EOF
  chmod +x "$MOCK/npm"
  cat > "$MOCK/node" <<'EOF'
#!/usr/bin/env bash
echo "v25.0.0"; exit 0
EOF
  chmod +x "$MOCK/node"
  export PATH="$MOCK:$PATH"
  export DEVFLOW_RENDER_CACHE="${BATS_TEST_TMPDIR}/render-deps"
  export DEVFLOW_RENDER_ASSUME_YES=1   # bypass consent in tests
  source "${REPO}/lib/utils.sh"; source "${REPO}/lib/render-deps.sh"
}

@test "resolver installs into the cache when globals lack the deps" {
  run render_deps_resolve
  assert_success
  assert [ -d "${DEVFLOW_RENDER_CACHE}/node_modules/canvas" ]
  assert_output --partial "${DEVFLOW_RENDER_CACHE}"   # echoes the chosen NODE_PATH dir
}

@test "resolver reuses the cache on a second call without reinstalling" {
  render_deps_resolve >/dev/null
  run render_deps_resolve
  assert_success
}
```

- [ ] **Step 2 — run FAIL → create `lib/render-deps.sh`:**

```bash
#!/usr/bin/env bash
# lib/render-deps.sh — resolve the 3 excalidraw-render npm deps without devflow init.
# Order: existing globals -> ~/.devflow/render-deps cache -> consent + npm i --prefix (no -g/sudo).
# Echoes the resolved node_modules-parent dir on stdout (caller sets NODE_PATH/EXCAL_NODE_MODULES).

RENDER_PKGS="canvas@3 excalidraw-to-svg @resvg/resvg-js"
RENDER_PKG_DIRS="canvas excalidraw-to-svg @resvg/resvg-js"

_render_deps_have() {  # <node_modules-dir> -> 0 if all 3 present
  local nm="$1" d
  for d in $RENDER_PKG_DIRS; do [[ -d "${nm}/${d}" ]] || return 1; done
  return 0
}

render_deps_resolve() {
  local cache="${DEVFLOW_RENDER_CACHE:-$HOME/.devflow/render-deps}"
  # 1) globals
  local gm; gm="$(npm root -g 2>/dev/null || echo "")"
  if [[ -n "$gm" ]] && _render_deps_have "$gm"; then echo "$gm"; return 0; fi
  # 2) cache
  if _render_deps_have "${cache}/node_modules"; then echo "${cache}/node_modules"; return 0; fi
  # 3) consent + install into cache
  if [[ "${DEVFLOW_RENDER_ASSUME_YES:-0}" != "1" ]]; then
    # caller (skill) should have gated via AskUserQuestion; CLI prompts here:
    printf 'Render deps (%s) not found. Install into %s now? [y/N] ' "$RENDER_PKGS" "$cache" >&2
    local ans; read -r ans || ans="n"
    case "$ans" in y|Y|yes) ;; *) echo "render deps not installed" >&2; return 1 ;; esac
  fi
  mkdir -p "$cache"
  # shellcheck disable=SC2086
  npm install --prefix "$cache" $RENDER_PKGS >&2 || { echo "npm install failed" >&2; return 1; }
  _render_deps_have "${cache}/node_modules" || { echo "deps still missing after install" >&2; return 1; }
  echo "${cache}/node_modules"
}
```

- [ ] **Step 3 — refactor `viz_render`** (`lib/visualizations.sh`) to use the resolver instead of dying:

```bash
  # replace the global_modules block with:
  source "${root}/lib/render-deps.sh"
  local nm; nm="$(render_deps_resolve)" || die "Could not resolve render deps."
  NODE_PATH="$nm" EXCAL_NODE_MODULES="$nm" node "$script" "$@" \
    || die "Diagram export failed."
```

- [ ] **Step 4 — run PASS; commit:**

```bash
git add lib/render-deps.sh lib/visualizations.sh bin/devflow tests/unit/render-deps.bats
git commit -m "feat(render): self-provision npm deps via lib/render-deps.sh (cache+consent, no -g)" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task D2: standalone diagrams-flow render (no bin/devflow)

**Files:** Modify `scripts/build-flows.sh` (bundle extras into the diagrams flow), `{devflow-plugin/skills,skills}/render-diagram/SKILL.md` (CLI-optional render step). Regenerate flows.

- [ ] **Step 1 — extend build-flows.sh** to bundle the renderer into the diagrams flow after the skill copy:

```bash
  if [[ "$flow" == "diagrams" ]]; then
    cp "${ROOT}/lib/excalidraw-export.cjs" "${outdir}/skills/render-diagram/excalidraw-export.cjs"
    cp "${ROOT}/lib/render-deps.sh"        "${outdir}/skills/render-diagram/render-deps.sh"
    cat > "${outdir}/skills/render-diagram/render.sh" <<'RS'
#!/usr/bin/env bash
# Standalone render launcher (no bin/devflow): resolve deps + run the bundled export.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "${here}/render-deps.sh"
nm="$(render_deps_resolve)"
NODE_PATH="$nm" EXCAL_NODE_MODULES="$nm" node "${here}/excalidraw-export.cjs" "$@"
RS
    chmod +x "${outdir}/skills/render-diagram/render.sh"
  fi
```

- [ ] **Step 2 — make render-diagram's render step CLI-optional** (canonical SKILL.md "Step 3: Render" — 3-copy). Replace the single command with:

```markdown
## Step 3: Render
Render deps are the `render-diagram` skill's OPTIONAL dep (handled by Preflight). If they were missing and the user consented to install (via Preflight's `AskUserQuestion`), export `DEVFLOW_RENDER_ASSUME_YES=1` for the render invocation so `render-deps.sh` installs non-interactively instead of blocking on `read` (which EOFs to "n" in a non-TTY Bash tool / `claude --print` / cron):

- If `devflow` is on PATH: `DEVFLOW_RENDER_ASSUME_YES=1 devflow visualizations render <path>/<name>.excalidraw`
- Else (standalone diagrams-flow install): `DEVFLOW_RENDER_ASSUME_YES=1 bash "$SKILL_DIR/render.sh" <path>/<name>.excalidraw`

(If the user declined the install, do NOT set the var — the resolver returns non-zero and you report the missing deps per Preflight.) Both write `<name>.svg` + `<name>.png` and print `PNG <abspath>` as the final line — capture it, then Read the PNG (Step 4).
```

> **Consent seam (B↔D wiring):** the single consent prompt that AC6 requires is Preflight's `AskUserQuestion` (B), NOT `render-deps.sh`'s interactive `read` fallback. The skill translates "user consented" into `DEVFLOW_RENDER_ASSUME_YES=1` on the render command; the resolver's own `read` is only a human-CLI fallback for someone running `devflow visualizations render` directly in a terminal.

- [ ] **Step 3 — regenerate + test** (existing flows.bats asserts the diagrams tree; add an assertion for `render.sh`):

```bash
@test "diagrams flow bundles a standalone render launcher + export script" {
  bash "${REPO}/scripts/build-flows.sh" >/dev/null
  assert [ -x "${REPO}/devflow-plugin/flows/diagrams/skills/render-diagram/render.sh" ]
  assert [ -f "${REPO}/devflow-plugin/flows/diagrams/skills/render-diagram/excalidraw-export.cjs" ]
}
```

- [ ] **Step 4 — run PASS; commit:**

```bash
git add scripts/build-flows.sh devflow-plugin/skills/render-diagram/SKILL.md skills/render-diagram/SKILL.md devflow-plugin/commands/render-diagram.md tests/unit/flows.bats devflow-plugin/flows
git commit -m "feat(flows): bundle standalone renderer in diagrams flow (render without bin/devflow)" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

# Phase E — diagram-complexity rule

### Task E1: rule text in template + init marker-block refresh

**Files:** Modify `templates/CLAUDE.md.tmpl`, `lib/init.sh`. Test `tests/unit/utils.bats` or a new `init` test for the block-replace helper.

- [ ] **Step 1 — add the rule to `templates/CLAUDE.md.tmpl`** (inside the block, before `<!-- /devflow -->`):

```markdown
## Diagram Complexity Rule

Before drawing any diagram, rate its complexity:
- 🟢 **simple** — linear / ≤4 nodes → plain ASCII is fine, no render needed.
- 🟡 **moderate** — fork-join, 5–8 nodes, or one crossing → OFFER a rendered Excalidraw (the **render-diagram** skill).
- 🔴 **complex** — bidirectional, multi-lane, >8 nodes, or cycles → render with the **render-diagram** skill AND show it inline via the Read tool.
```

> **Namespace-agnostic on purpose:** reference the **render-diagram skill by name**, NOT a hardcoded `/devflow:render-diagram` slash. A flow-only install exposes it as `/devflow-diagrams:render-diagram`, so a hardcoded `/devflow:` slash would dangle for those users (same bug class as the write-spike reference). This exact agnostic block is reused verbatim in E2's skill-embedding.

- [ ] **Step 2 — failing test** for an idempotent block-replace helper (`_inject_devflow_block`) in init.sh:

```bash
@test "_inject_devflow_block replaces the existing devflow block (idempotent refresh)" {
  source "${REPO}/lib/init.sh"
  local f="${BATS_TEST_TMPDIR}/CLAUDE.md"
  printf 'pre\n<!-- devflow -->\nOLD\n<!-- /devflow -->\npost\n' > "$f"
  printf '<!-- devflow -->\nNEW RULE\n<!-- /devflow -->\n' > "${BATS_TEST_TMPDIR}/tmpl"
  _inject_devflow_block "$f" "${BATS_TEST_TMPDIR}/tmpl"
  run grep -c "NEW RULE" "$f"; assert_output "1"
  run grep -c "OLD" "$f";       assert_output "0"
  run grep -c "<!-- devflow -->" "$f"; assert_output "1"   # exactly one block
  run grep -c "^pre$" "$f"; assert_output "1"              # surrounding content preserved
}
```

- [ ] **Step 3 — run FAIL → add `_inject_devflow_block`** to `lib/init.sh` (awk-based, bash-3.2-safe) and call it from step 3 of `devflow_init` instead of append-only:

```bash
# _inject_devflow_block <target-file> <template-file>
# Replaces content between <!-- devflow --> and <!-- /devflow --> with the template
# (which itself contains the markers). Appends if no block present. Idempotent.
_inject_devflow_block() {
  local target="$1" tmpl="$2"
  [[ -f "$target" ]] || { cp "$tmpl" "$target"; return 0; }
  if grep -q '<!-- devflow -->' "$target" && grep -q '<!-- /devflow -->' "$target"; then
    awk -v tmpl="$tmpl" '
      /<!-- devflow -->/ { while ((getline line < tmpl) > 0) print line; close(tmpl); skip=1; next }
      /<!-- \/devflow -->/ { if (skip) { skip=0; next } }
      !skip { print }
    ' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"
  else
    printf '\n' >> "$target"; cat "$tmpl" >> "$target"
  fi
}
```

> The init step-3 call becomes `_inject_devflow_block "${claude_home}/CLAUDE.md" "${templates_dir}/CLAUDE.md.tmpl"` (replaces the current grep-guarded append). Existing installs now refresh on re-init; new installs get the full block.

- [ ] **Step 4 — run PASS; commit:**

```bash
git add templates/CLAUDE.md.tmpl lib/init.sh tests/unit/utils.bats
git commit -m "feat(diagrams): ship complexity rule via template + idempotent init block refresh" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task E2: embed the rule atop diagram-producing skills

**Files:** Modify (3-copy each): render-diagram, spec-feature, codebase-walkthrough, update-visualizations, architecture-decision SKILL.md + command `.md`. Regenerate flows (render-diagram is in the diagrams flow).

- [ ] **Step 1 — insert the rule** (same 4-line 🟢🟡🔴 block as E1, as a `> **Diagram complexity:**` callout) near the top of each of the 5 skills, all 3 copies, byte-identical body.

- [ ] **Step 2 — regenerate flows** (`make flows`) so the diagrams-flow render-diagram copy carries it; run `make flows-check` (must pass), `make test-unit`.

- [ ] **Step 3 — commit:**

```bash
make flows
git add devflow-plugin/skills/*/SKILL.md skills/*/SKILL.md devflow-plugin/commands/*.md devflow-plugin/flows
git commit -m "feat(diagrams): embed complexity rule in diagram-producing skills" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

# Finish

### Task F1: full verification + MR

- [ ] **Step 1 — regenerate + full test:**

```bash
make flows && make flows-check && make test && make test-unit
bash -n scripts/build-flows.sh lib/render-deps.sh lib/deps.sh   # bash-3.2 syntax sanity
```

- [ ] **Step 2 — manual smoke** (per spec AC1/AC6/AC7): install `devflow-review` alone in a throwaway dir → assert only review/review-document/write-spike; clear `~/.devflow/render-deps`, render a diagram (consent path); render with only the diagrams flow (no `bin/devflow`).
- [ ] **Step 3 — version-bump dry check:** `devflow release` (preview) shows the bump; confirm flow plugin.json + badges would stamp.
- [ ] **Step 4 — hand to `/devflow:finish-feature`** (runs verification, creates the ONE MR, retains learnings). Merge ⇒ release; do NOT use `[skip release]`; never write the literal marker in commit prose.

---

## Self-Review (against the spec)

**Spec coverage:** AC1 (A1/A3 + smoke F1) · AC2 (A1 namespacing + plugin.json non-recursion verified A1 Step 4) · AC3 (B1/B2) · AC4 (B2 degrade + non-interactive default) · AC5 (C1/C2; namespacing nuance documented) · AC6 (D1) · AC7 (D2) · AC8 (E1/E2) · AC9 (A2) · AC10 (A3). All 10 covered.

**Placeholder scan:** every code step carries real content. `lib/finish-feature` exact edit point (sensitive gate) is the one "find the existing checks" reference — acceptable (it's an existing, locatable section); executor greps for the pre-PR check list.

**Type/name consistency:** `render_deps_resolve` (D1) reused verbatim in D2's `render.sh`; `_inject_devflow_block` (E1) signature matches its call; `devflow_deps`/`deps check` consistent across B3 + bin/devflow; flow names review/diagrams/jira consistent across manifest, marketplace, tests, version-stamp globs.

**Known executor cautions:** (1) `build-flows.sh` top-level `local` keyword — drop if running under strict shellcheck. (2) release ordering — regen flows BEFORE stamping (A3 note). (3) `claude plugin validate` is a manual gate (A1 Step 4), not a bats test (no CLI in CI sandbox). (4) bash 3.2: no assoc arrays anywhere (manifest is pipe-delimited), test new scripts with `/bin/bash`.

**Advisor pass (pre-handoff) — 4 fixes applied:** (1) A2 drift test now tampers the CANONICAL source (the generated copy would be wiped by `build-flows`' `rm -rf` before the diff, so it could never fail) and runs against a committed repo copy. (2) E rule text is namespace-agnostic ("the render-diagram skill") — a `/devflow:` slash dangles in a flow-only install. (3) Consent seam wired: Preflight's `AskUserQuestion` consent → `DEVFLOW_RENDER_ASSUME_YES=1` on the render command, so the resolver never blocks on a non-TTY `read`. (4) `build-flows.sh` while-read keeps the last manifest line without a trailing newline (`|| [[ -n "$flow" ]]`). The `_inject_devflow_block` awk helper was reviewed and confirmed correct.
