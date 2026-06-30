3/3 green. Now emit the fixed-schema audit.

---

## Determinism Audit: new-feature

### Findings

| ID | Location | Axis | Severity | Effort | Nondeterminism | Deterministic fix |
|----|----------|------|----------|--------|----------------|-------------------|
| D1 | Preamble step 1 + Step 1, ticket ID extraction | offload | high | S | Model reads branch name and mentally applies `[A-Z]+-[0-9]+` regex | `git branch --show-current \| grep -oE '[A-Z]+-[0-9]+' \|\| echo none` |
| D2 | Step 1, base branch detection | offload | medium | S | Model infers base branch from which `git log` succeeds | `git rev-parse --verify main >/dev/null 2>&1 && echo main \|\| echo master` |
| D3 | Step 1, main/master guard | offload | medium | S | English: "If the current branch is `main` or `master`, this skill does not apply" | `case "$BRANCH" in main\|master) die "…"; esac` |
| D4 | Step 2, Hindsight query construction | offload | low | S | "domain area from branch name" is model-interpreted | `git branch --show-current \| sed 's|.*/||; s/-/ /g'` → last path segment as query term |
| D5 | Step 3, workspace context output block | constrain | medium | S | No instruction pins format; model may add prose, fences, or reorder fields | Add: "Output only the block below, no prose, no fences" before the template; pin field order |
| D6 | Step 4, branch-name sufficiency check | offload | low | S | "descriptive enough" is a fuzzy quantifier | Replace with: if branch name contains `/` and last segment has >2 words, treat as descriptive; else ask |

### Findings (machine-readable)

```yaml
skill: new-feature
findings:
  - id: D1
    location: "Preamble step 1 + Step 1, ticket ID extraction"
    axis: offload
    severity: high
    effort: S
    nondeterminism: "Model reads branch name and mentally applies [A-Z]+-[0-9]+ regex"
    fix: "git branch --show-current | grep -oE '[A-Z]+-[0-9]+' || echo none"
  - id: D2
    location: "Step 1, base branch detection"
    axis: offload
    severity: medium
    effort: S
    nondeterminism: "Model infers base from which git log command succeeds"
    fix: "git rev-parse --verify main >/dev/null 2>&1 && echo main || echo master"
  - id: D3
    location: "Step 1, main/master guard in English"
    axis: offload
    severity: medium
    effort: S
    nondeterminism: "English prose guard; model may miss edge cases (e.g. develop, trunk)"
    fix: "case \"$BRANCH\" in main|master) echo 'not a feature branch'; exit 1;; esac"
  - id: D4
    location: "Step 2, Hindsight query domain area"
    axis: offload
    severity: low
    effort: S
    nondeterminism: "\"domain area from branch name\" is model-interpreted; varies per run"
    fix: "git branch --show-current | sed 's|.*/||; s/-/ /g'"
  - id: D5
    location: "Step 3, workspace context output block"
    axis: constrain
    severity: medium
    effort: S
    nondeterminism: "No instruction pins output format; prose/fences/reordering possible"
    fix: "Add 'Output only the block below, no prose, no fences' before the template"
  - id: D6
    location: "Step 4, branch-name sufficiency check"
    axis: offload
    severity: low
    effort: S
    nondeterminism: "\"descriptive enough\" is a fuzzy quantifier with no threshold"
    fix: "If last path segment has >2 hyphen-separated words, treat as descriptive"
```

### Assertions → `skills/new-feature/determinism.promptfooconfig.yaml`

Written to disk. 3 Axis B tests (D5), all passing (3/3 green on `promptfoo eval`).

- **D5-a**: `icontains` all four required keys (`Branch:`, `Base:`, `Project:`, `Ticket:`)
- **D5-b**: `not-icontains "```"` — output block must not be fence-wrapped
- **D5-c**: `icontains "Feature Workspace"` — section header pinned

Axis A bats tests (D1–D4, D6): apply after refactor — the bash extractions don't exist as functions yet.

### ROI

Top fix: **D1** (severity=high, effort=S) — ticket ID extraction by `grep -oE` replaces mental regex; wrong ID cascades to all Hindsight namespacing and the terminal window title.

Order: **D1 > D2 > D3 > D5 > D4 > D6**
