# Implementation Plan: Finish-Feature Visualization Integration

**Date:** 2026-03-10
**Spec:** `docs/superpowers/specs/2026-03-10-finish-feature-visualization-integration-design.md`
**Branch:** feat/review-pr-description

## Execution Strategy

Two parallel tracks, executed via sub-agents:
- **Track A** — Skill fix (single agent)
- **Track B** — Visualization audit (coordinator + specialist agents)

Track A and Track B are independent and run simultaneously.

---

## Track A — Finish-Feature Skill Fix

### Task A1: Add visualization check step to finish-feature.md

**File:** `devflow-plugin/commands/finish-feature.md`

**What to do:**

Insert a new **Step 4** between current Step 3 (stage & commit) and current Step 4 (PR description strategy). Renumber all subsequent steps (current 4→5, 5→6, 6→7, 7→8, 8→9, 9→10).

The new Step 4 content:

```markdown
4. **Check and update visualizations.** If this project has architecture visualizations, check if any need updating.

   First, check if a visualization directory exists:
   ```bash
   # Check common locations
   ls -d visualizations/ docs/visualizations/ docs/diagrams/ 2>/dev/null | head -1
   ```

   Also check for config:
   ```bash
   cat .devflow/visualizations.json 2>/dev/null || cat ~/.config/devflow/visualizations.json 2>/dev/null
   ```

   **If no visualization directory or config found:** Skip this step with a one-line note: "No visualization directory found, skipping visualization check."

   **If visualizations exist:**
   - Read the visualization skill for guidance: `Read skills/visualizations/update-visualizations.md`
   - Analyze the full feature branch diff (`git diff main..HEAD` or `git diff master..HEAD`) to identify changes that affect architecture, workflows, or integrations
   - Read the visualization index (`<viz-path>/README.md`) and any potentially affected diagram files
   - Map changes to affected visualizations using the heuristics from the skill's Step 4
   - **If no diagrams need updating:** Say "No visualization updates needed" and move on
   - **If diagrams need updating:** Present a TLDR to the user:
     ```
     ## Visualization Updates Proposed

     **[diagram-file.md]:** <1-2 sentence gist of what would change>
     **[another-diagram.md]:** <1-2 sentence gist>

     Confirm to apply these updates, or skip to continue without changes.
     ```
   - **Wait for user confirmation** before making any changes
   - If confirmed: update the diagram files, then stage and commit:
     ```bash
     git add <viz-path>/
     git commit -m "docs: update visualizations for [brief feature description]"
     ```
   - Do NOT trigger first-run visualization setup (creating folders, README, defaults) inside this flow

   > **Note:** This step uses plain-text summaries since mermaid diagrams cannot be rendered in the terminal. Describe what was added, removed, or modified in each diagram.
```

Also update the "CRITICAL" note after the PR creation step (now Step 7) to reference the correct step numbers: "Steps 8-10 below are mandatory."

Update the Important section at the bottom to add:
```markdown
- The visualization check (step 4) is a lightweight pass — skip silently if no viz directory exists.
```

**Verification:** Read the edited file and confirm step numbering is correct (1-10), all cross-references are updated.

---

## Track B — Visualization Audit

### Task B1: Audit commits since last visualization edit (Coordinator)

**Research only — do not edit files.**

Analyze what changed between commit `d53f021` (last viz edit) and current `main` HEAD. The commits to analyze:

```
a578596 fix/review-command-hang merge
188dfd5 fix(hooks): clean up stop-finish-prompt hook stderr output
4b3d521 chore: add review-command-hang task file
0a3eeaf Merge PR #7
35d37ff feat(cli): fetch PR/MR description for context and add structured output format
b8178e9 Merge PR #8
d6ac83c feat(skills): add template-aware PR description strategy
9e75b40 Merge PR #9
799ab64 fix(skills): fix writing-plans wrapper loading and improve PR creation
96be68f Merge PR #10
ef63ef8 fix(skills): use devflow done for cleanup in finish-feature
36e6e27 Merge PR #11
3503463 feat(skills): add worktree cleanup option to finish-feature
a98a43f Merge PR #12
072fc89 fix(hooks): fix prompt-fetch-rebase blocking loop and standardize tool naming
f9af22e docs: add design and implementation plan for finish-feature post-PR continuation
ab16275 fix(skills): correct agent-deck launch flags in writing-plans
dd0fc22 feat(hooks): add PostToolUse hook for post-PR continuation prompt
c57db0d feat(hooks): add PR/MR detection to stop hook — allow stop when PR exists
997e602 feat(init): register PostToolUse hook for post-PR continuation
6d4fe53 Merge PR #13
347d3d1 feat(skills): add explicit continuation instruction after PR creation in finish-feature
2b3e2e8 Merge PR #14
```

**Produce a brief per affected diagram:**

#### Brief for `devflow-ecosystem.md`:
- **Hooks architecture**: PostToolUse hook and Stop hook PR detection are new. These belong in the ecosystem's cross-layer connections or as annotations on the Skills layer (L5) since hooks are process discipline.
- **CLI commands table**: `devflow review <pr-url>` was already added to the viz. Check if any new CLI commands were added.
- **Skill-to-Layer table**: finish-feature now has 10 steps (added viz check). The table entry may need updating.
- **PR description fetch**: `devflow review` now fetches PR/MR description for context — already reflected in viz from d53f021.

#### Brief for `development-workflow.md`:
- **Phase 4 (Finishing)**: The "Agent Actions" subgraph needs a new node for "Check/update visualizations" between "Commit changes" and "git push". This reflects the new Step 4 in finish-feature.
- **High-Level Flow**: May need a "Viz Check" node between COMMIT and MR, or incorporate it into the COMMIT node label.
- **Tool Active table**: Add a visualization column or note that visualizations are checked during the Finish phase.
- **Worktree cleanup**: finish-feature now offers `devflow done` for cleanup. The terminal actions subgraph references `agent-deck worktree finish` and `wt drop` — should also show `devflow done`.

#### Brief for `code-review-architecture.md`:
- **PR description strategy**: finish-feature now has a template-aware PR description strategy (auto-generate, repo-template, custom). This is part of the review/PR pipeline but not strictly code review architecture. Probably not needed here since it's more of a skills workflow concern.
- **Integration Points diagram (Section 4)**: The `/finish-feature` skill now has the visualization step. The diagram shows finish-feature triggering `devflow check` — this is still accurate. No change needed.
- **Verdict**: Likely no changes needed for this file.

### Task B2: Update `devflow-ecosystem.md`

**File:** `visualizations/architecture/devflow-ecosystem.md`

**Context from coordinator:**
- PostToolUse hook and Stop hook PR detection are new hook mechanisms
- Hooks live in `lib/hooks/` and are part of the process discipline layer (L5)
- The Skill-to-Layer table should reflect finish-feature's updated step count

**Changes to make:**
1. **Section 3 (Skill-to-Layer table):** Update the `/finish-feature` row — it now touches L4 + L1 + visualizations. Update the "What it does" description to mention viz check.
2. **Section 5 (CLI Commands table):** Add `devflow done <branch>` command (worktree cleanup) and `devflow viz` commands (list, open, update, config) if not already present.

**Style guide:** Follow `visualizations/README.md` conventions — init blocks, classDef palette, section structure.

### Task B3: Update `development-workflow.md`

**File:** `visualizations/workflows/development-workflow.md`

**Context from coordinator:**
- finish-feature now has a visualization check step after commit, before push
- Worktree cleanup now uses `devflow done` (not just `agent-deck worktree finish` / `wt drop`)

**Changes to make:**
1. **Section 1 (High-Level Flow):** Add a `VIZ["Update Visualizations"]` node between `COMMIT` and `MR`. Style it with `reviewStyle` or a new style. Connect: `COMMIT --> VIZ --> MR`.
2. **Section 5 (Phase 4 — Finishing):** In the "Agent Actions" subgraph, add `F_VIZ["Check/update visualizations<br/>(if viz directory exists)"]` between `F_COMMIT` and `F_PUSH`. Connect: `F_COMMIT --> F_VIZ --> F_PUSH`.
3. **Section 5 (Phase 4):** Update terminal actions subgraph — change `F_FINISH` label to include `devflow done` as the recommended cleanup command. Keep `wt drop` as alternative.
4. **Section 6 (Tool Active table):** In the "Finish (Agent)" row, add a note about visualization check.

**Style guide:** Follow `visualizations/README.md` conventions.

### Task B4: Review `code-review-architecture.md` (verification only)

**File:** `visualizations/architecture/code-review-architecture.md`

**Context from coordinator:**
- PR description strategy was added to finish-feature but is not a code review architecture concern
- Integration points diagram already correctly shows finish-feature triggering devflow check

**Expected outcome:** No changes needed. Verify and confirm.

---

## Commit Strategy

- **Track A commit:** `feat(skills): add visualization check step to finish-feature`
- **Track B commit:** `docs: update visualizations for hooks architecture and viz check step`

---

## Verification

After both tracks complete:
1. Read `devflow-plugin/commands/finish-feature.md` — confirm 10 steps, correct numbering, cross-references updated
2. Read all 3 visualization files — confirm diagrams are syntactically valid mermaid, style guide followed
3. Run `git log --oneline HEAD~5..HEAD` — confirm clean commit history
