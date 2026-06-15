# Test Inventory: Flow-separated marketplace + per-skill optional-deps

**Generated:** 2026-06-15
**Ticket:** TICKET-000
**Branch:** hardcore-raman-6c040e (base v0.3.0)
**Spec:** docs/specs/flow-marketplace-and-optional-deps.md
**Plan:** docs/plans/2026-06-12-flow-marketplace-and-optional-deps-plan.md
**Design:** docs/plans/2026-06-12-flow-marketplace-and-optional-deps-design.md
**Build order:** B → C → A → D → E → finish (one MR, merge ⇒ release)

16 new failing test cases across 6 bats files (4 new, 2 extended), all verified RED for the
right reason. Plus 4 manual-only gates (no CLI / prompt-driven) that bats cannot cover.

---

## Coverage map (AC → test)

Coverage column: **BATS** = fully covered by a failing bats test · **BATS(mech)** = bats covers
the mechanism/artifact, runtime behaviour is prompt-driven/manual · **MANUAL** = no bats; manual or
prompt-driven gate.

| AC | Coverage | Test file | Test name | Status |
|---|---|---|---|---|
| AC1: single-flow install pulls ONLY review + review-document + write-spike | MANUAL | — | manual gate M2 (install smoke) | — |
| AC2: full `devflow` plugin unchanged, no flow skills double-listed | BATS(mech) | tests/unit/flows.bats | "build-flows generates each flow as a self-contained mini-plugin" | RED |
| AC2 (cont.) | BATS(mech) | tests/unit/flows.bats | "flow plugin.json name is devflow-<flow> and version matches the full plugin" | RED |
| AC2 (non-recursion / install) | MANUAL | — | manual gate M1 + M4 (`jq .skills[] \| grep -c flows/`) | — |
| AC3: every in-scope skill has requirements.json | BATS | tests/unit/requirements.bats | "every in-scope skill has a valid requirements.json with skill/required/optional keys" | RED |
| AC3 (dep shape) | BATS | tests/unit/requirements.bats | "each dep has name, check, why" | RED |
| AC3 (required-missing detection) | BATS | tests/unit/deps.bats | "deps check exits non-zero and names the dep when a required dep is missing" | RED |
| AC3 (Preflight block + STOP / AskUserQuestion runtime) | MANUAL | — | prompt-driven (Preflight block in SKILL.md) | — |
| AC4: skill runs to completion with Hindsight unavailable (degrade) | BATS(mech) | tests/unit/requirements.bats | "hindsight is declared OPTIONAL (never required) wherever it appears" | RED |
| AC4 (degrade runtime, non-interactive default) | MANUAL | — | prompt-driven (Preflight degrade path) | — |
| AC5: write-spike resolves; example committed; real config path | BATS(mech) | tests/unit/flows.bats | "build-flows generates ... flows/review/skills/write-spike/{SKILL.md,requirements.json}" | RED |
| AC5 (symlink gone / `/devflow:write-spike` resolves) | MANUAL | — | filesystem + plugin-resolution gate | — |
| AC6: render on deps-cleared machine after single consent | BATS(mech) | tests/unit/render-deps.bats | "resolver installs into the cache when globals lack the deps" | RED |
| AC6 (cont.) | BATS(mech) | tests/unit/render-deps.bats | "resolver reuses the cache on a second call without reinstalling" | RED |
| AC6 (real npm install + consent prompt) | MANUAL | — | manual gate M3 (deps-cleared render) | — |
| AC7: render-diagram renders with only the diagrams flow (no bin/devflow) | BATS(mech) | tests/unit/flows.bats | "diagrams flow bundles a standalone render launcher + export script" | RED |
| AC7 (actual standalone render) | MANUAL | — | manual gate M2 (single-flow render) | — |
| AC8: after init, CLAUDE.md has the rule; idempotent refresh | BATS | tests/unit/utils.bats | "_inject_devflow_block replaces the existing devflow block (idempotent refresh)" | RED |
| AC8 (template content + 5-skill embedding present) | MANUAL | — | grep/manual (not bats-locked; see Considered) | — |
| AC9: `make flows` idempotent; edit-without-regen fails flows-check + make test | BATS | tests/unit/flows.bats | "flow copies are byte-identical to canonical skill SKILL.md" | RED |
| AC9 (drift detection) | BATS | tests/unit/flows.bats | "flows-check fails when a canonical skill changed but flows were not regenerated" | RED |
| AC10: release bump stamps every flow plugin.json (no version drift) | BATS | tests/unit/release.bats | "bump_all_versions stamps flow plugin.json files" | RED |
| AC10 (flow command badge stamp) | MANUAL | — | not bats-locked; see Considered | — |
| (B3 happy path) deps check reports OK when required present | BATS | tests/unit/deps.bats | "deps check reports OK when all required present" | RED |
| (B1) render-diagram requires node + npm | BATS | tests/unit/requirements.bats | "render-diagram requires node and npm" | RED |
| (B4) registry mirrors requires/optional name-lists | BATS | tests/unit/requirements.bats | "registry mirrors requires/optional name-lists for in-scope skills" | RED |

**Fully bats-covered ACs:** AC9, AC10. **Mechanism-bats + manual:** AC2, AC3, AC4, AC5, AC6, AC7, AC8. **Fully manual:** AC1.

---

## New test files (16 cases)

| File | New cases | Tasks | New / extended |
|---|---|---|---|
| tests/unit/requirements.bats | 5 | B1, B4 | NEW |
| tests/unit/deps.bats | 2 | B3 | NEW |
| tests/unit/flows.bats | 5 | A1, A2, D2 | NEW |
| tests/unit/render-deps.bats | 2 | D1 | NEW |
| tests/unit/release.bats | +1 | A3 | EXTENDED |
| tests/unit/utils.bats | +1 | E1 | EXTENDED |

### RED-reason verification (Phase 1.5 — all confirmed)

- requirements.bats: missing `requirements.json` files; `found`-guard fires (`[ 0 -ge 1 ]`); registry bool `false`.
- deps.bats: `Unknown command: deps`; missing-dep test's `--partial` substring strengthening fires.
- flows.bats: `build-flows.sh: No such file` (127); drift test → `No rule to make target 'flows-check'`, `--partial "flows out of date"` strengthening fires.
- render-deps.bats: setup cannot `source lib/render-deps.sh` (module-not-found class — acceptable for new code). Bodies (npm-stub install path, cache reuse, `assert_output --partial "$DEVFLOW_RENDER_CACHE"`) were GREEN-verified by temporarily dropping in the plan's D1 `render-deps.sh`, re-running (both passed), then removing it — so the stub + assertion wiring is validated, not just the setup-fail.
- release.bats (new): bump runs OK, flow `plugin.json` stays `0.1.0` ≠ `9.9.9`.
- utils.bats (new): `_inject_devflow_block: command not found`.

### Deviations from the plan's verbatim tests (3 RED-correctness fixes, advisor-confirmed)

1. **requirements.bats tests 2 & 4** — added a `found` guard around the `skills/*/requirements.json`
   glob. With nullglob off and zero files, the glob stays literal and test 2's bare `assert_failure`
   passed *vacuously* (jq-on-missing-file fails). The guard makes RED fail because no file exists yet,
   and the glob still covers write-spike's file at GREEN (Phase C).
2. **flows.bats drift test (A2)** — added `assert_output --partial "flows out of date"`. At RED `make`
   errors `No rule to make target`, which satisfies bare `assert_failure` vacuously; the substring
   forces RED to fail because the real drift message is absent until A2 lands.
3. **flows.bats drift test (A2) — worktree isolation** — the plan's `cp -R "${REPO}" "$work"` copies
   this **worktree's** `.git` *gitlink file*, so `git -C "$work" commit` would resolve through it and
   could advance the real `hardcore-raman` branch. Added `rm -rf "$work/.git" && git init` to isolate
   the copy (also required for the GREEN path: drift needs a committed standalone `flows/` baseline).
   Verified after running: real branch HEAD still `efc9b8a`, no junk commits.
4. **release.bats (A3)** — the plan's snippet referenced an undefined `${REPO}` and re-`cp -R`'d the
   repo; rebuilt as a minimal standalone fixture + a generated flow `plugin.json` to stamp. Asserts
   only `.version` (sidesteps the `[devflow v…]` vs `[X.Y.Z]` command-badge format question).

---

## Manual-only gates (NOT bats — no CLI in sandbox / prompt-driven)

| ID | Gate | Covers | How to run |
|---|---|---|---|
| M1 | `claude plugin validate devflow-plugin` | AC2 structure | after A1: `claude plugin validate devflow-plugin 2>&1 \| tail -20` |
| M2 | Single-flow install smoke | AC1, AC7 | install `devflow-review` alone in a throwaway project → assert only review/review-document/write-spike present; render a diagram with only `devflow-diagrams` installed (no `bin/devflow` on PATH) |
| M3 | Deps-cleared render consent | AC6 | `rm -rf ~/.devflow/render-deps`; `devflow visualizations render <f>.excalidraw` → single consent prompt → PNG, no `-g`/sudo |
| M4 | Full-plugin non-recursion of flows | AC2 | `jq -r '.skills[]' devflow-plugin/.claude-plugin/plugin.json \| grep -c flows/` → expect `0` |

---

## Considered but not added

- **npm cache partially populated / corrupt** (spec Edge Case) — `_render_deps_have` requires all 3
  package dirs, so a partial cache takes the *same* reinstall path as `render-deps.bats` RD1
  ("globals lack the deps"). A separate finer-grained case is deferred unless the resolver grows
  per-package install logic at impl time.
- **flows.manifest references a nonexistent skill → build-flows fails cleanly** (spec Edge Case) —
  the plan's `build-flows.sh` already guards (`[[ -d ... ]] || { echo "unknown skill"; exit 1; }`).
  Not separately locked to keep the locked set aligned with the advisor-reviewed plan; low risk
  (a single guarded branch). Add at impl time if desired.
- **requirements.json MISSING for a skill → preflight no-ops** (spec Edge Case) — Preflight is
  prompt-driven (reads the sibling file, skips if absent); `deps check`'s `_deps_resolve_file` dies
  with "No requirements.json". Not bats-locked beyond the existing deps.bats `--file` path.
- **Optional-dep prompt under non-interactive run defaults to "continue without"** (spec Edge Case,
  AC4) — `AskUserQuestion` behaviour, not bats-testable. The render path's `DEVFLOW_RENDER_ASSUME_YES`
  seam is exercised indirectly by render-deps.bats (the stub sets it to bypass consent).
- **write-spike with neither real nor example config → errors with expected path** (spec Edge Case,
  AC5) — skill-runtime behaviour, MANUAL.
- **node <25 vs ≥25 → canvas@3+ pin** (spec Edge Case) — needs real npm; the mock does not version-check.
  Verified by code-review of `RENDER_PKGS` + manual gate M3, not bats.
- **AC8 template content + 5-skill rule embedding presence** — could be a grep-based bats test, but
  the plan scoped E to the `_inject_devflow_block` helper only; embedding presence is a manual/grep
  check at finish. `_inject_devflow_block` idempotency IS locked (utils.bats).
- **AC10 flow command-badge stamp** — `release.bats` locks the flow `plugin.json` version stamp; the
  flow command-badge `[X.Y.Z]` stamp (same A3 loop) is left to the existing command-badge test pattern
  + manual diff, not a separate locked case.

---

## Pre-existing conditions (NOT introduced by this phase — for the impl phase's awareness)

- **tests/lib/bats-{support,assert} submodules were uninitialised in this worktree.** Ran
  `git submodule update --init --recursive` so the harness loads. A fresh worktree needs this before
  any bats run. (No tree changes; submodules sit at their pinned commits.)
- **Two `tests/unit/release.bats` tests fail pre-existing, in code this change never touches.** Both
  are UNRELATED to the locked feature; the lock-feature baseline is the 16 new cases above. The impl
  phase should not attribute either to this feature.
  - **Test 14 ("bump_all_versions updates all version files")** — fails under bats, but
    `bump_all_versions` **passes standalone under real `bash` (`EXIT=0`)**, under `set -eo pipefail`,
    and under a replicated `_common_setup` env. → a **bats-harness/environment quirk**, not a
    base-branch code failure.
  - **Test 5 ("parse_conventional_commits returns none for only chore: commits")** — fails under
    bats **and under real `bash` standalone**: `_parse_conventional_commits` returns `patch` (not the
    expected `none`) for a repo whose only post-tag commit is `chore:`. → a **genuine pre-existing
    parse discrepancy**, mechanism undetermined, in logic this change never touches. Flagged as a
    separate follow-up; not in scope for lock-tests (writes failing tests for the new feature only).

---

## Framework

- **bats-core 1.13.0** (`/opt/homebrew/bin/bats`); **jq** (`/usr/bin/jq`).
- Helpers: `tests/helpers/{common,assertions,mocks}.bash`; submodules `tests/lib/bats-{support,assert}`.
- New files use file-scope `load '../helpers/common'` (+ `assertions`/`mocks`) with a self-contained
  `setup()`; extended files (release.bats, utils.bats) keep their existing `_common_setup`/`source_lib` setup.
- No jest/vitest — bats only, run via `make test-unit` (`bats tests/unit/`).

## Verification command

```bash
# In a fresh worktree, initialise the bats submodules first:
git -C /Users/andrejorgelopes/dev/.worktrees/devflow/hardcore-raman-6c040e submodule update --init --recursive

# Run only the locked feature's test files:
cd /Users/andrejorgelopes/dev/.worktrees/devflow/hardcore-raman-6c040e
bats tests/unit/requirements.bats tests/unit/deps.bats tests/unit/flows.bats \
     tests/unit/render-deps.bats tests/unit/release.bats tests/unit/utils.bats

# Or the whole unit suite (includes the 2 pre-existing reds noted above):
make test-unit
```
