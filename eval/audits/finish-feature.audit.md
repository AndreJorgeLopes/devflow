## Determinism Audit: finish-feature

### Findings

| ID | Location | Axis | Severity | Effort | Nondeterminism | Deterministic fix |
|----|----------|------|----------|--------|----------------|-------------------|
| D1 | Preamble step 1, ticket extraction | offload | medium | S | "Detect ticket ID" — model reads branch name by eye | `git branch --show-current \| grep -oE '[A-Z]+-[0-9]+' \|\| echo none` |
| D2 | Step 1, branch guard | offload | high | S | "Confirm you are on a feature branch" — English confirmation | `case "$(git branch --show-current)" in main\|master) die "on protected branch"; esac` |
| D3 | Step 4a, design-doc path | offload | medium | M | "find its path via the frozen-state file's 'Source-of-truth artefacts'" — model scans prose | `grep -oE '[^ ]+\.(md\|pdf\|txt)' .devflow/state/"$BRANCH"/*.md \| head -1` |
| D4 | Step 4b–c, review gate output | constrain | medium | S | Subagent findings returned as free text; "present by severity" has no schema | Pin findings to a fixed table: `| Finding | Severity | Source |` — forbid prose blobs, require a machine-readable block |
| D5 | Step 5, TODO/FIXME scan | offload | medium | S | "grep the feature diff for TODO/FIXME" — instructional; model may narrate instead of running bash | `git diff "$(git merge-base origin/main HEAD)"..HEAD \| grep -E '^\+.*(TODO\|FIXME)'` |
| D6 | Step 6, commit message format | constrain | low | S | "Follow conventional commits format" — no schema; scope/body vary per run | Require `^(feat\|fix\|refactor\|chore)\([^)]+\): .+` in the generated line; forbid body > 72 chars on subject |
| D7 | Step 7, PR body format | constrain | medium | S | PR body described as "2-3 bullet points, Ticket reference, Testing notes" — free text | Pin template with required sections headings: `## Summary`, `## Ticket`, `## Testing` |
| D8 | Step 9, commit/file counts | offload | low | S | `<count>` placeholders — model narrates from memory | `git rev-list --count main..HEAD`; `git diff --stat main..HEAD \| tail -1 \| grep -oE '[0-9]+ files changed'` |

---

### Findings (machine-readable)

```yaml
skill: finish-feature
findings:
  - id: D1
    location: "Preamble step 1, ticket extraction"
    axis: offload
    severity: medium
    effort: S
    nondeterminism: "Model reads branch name and extracts ticket ID by judgment; regex is given but execution is not pinned to bash"
    fix: "git branch --show-current | grep -oE '[A-Z]+-[0-9]+' || echo none"

  - id: D2
    location: "Step 1, feature branch guard"
    axis: offload
    severity: high
    effort: S
    nondeterminism: "English 'Confirm you are on a feature branch (not main/master)' — model may proceed on main if it misreads output"
    fix: "case $(git branch --show-current) in main|master) die 'on protected branch'; esac"

  - id: D3
    location: "Step 4a, design-doc path extraction"
    axis: offload
    severity: medium
    effort: M
    nondeterminism: "Model scans frozen-state prose for a doc path; different runs may pick different artefacts"
    fix: "grep -oE '[^ ]+\\.(md|pdf|txt)' .devflow/state/$BRANCH/*.md | head -1"

  - id: D4
    location: "Step 4b-c, review gate findings format"
    axis: constrain
    severity: medium
    effort: S
    nondeterminism: "Subagent findings are free text; 'present by severity' has no schema; undiffable across runs"
    fix: "Pin findings to a required table format | Finding | Severity | Source | with explicit 'no prose outside the table'"

  - id: D5
    location: "Step 5, TODO/FIXME deferral scan"
    axis: offload
    severity: medium
    effort: S
    nondeterminism: "Instructional 'grep the feature diff for TODO/FIXME' — model may narrate result instead of running bash"
    fix: "git diff $(git merge-base origin/main HEAD)..HEAD | grep -E '^\\+.*(TODO|FIXME)'"

  - id: D6
    location: "Step 6, commit message format"
    axis: constrain
    severity: low
    effort: S
    nondeterminism: "Conventional commits format described in English; scope, body, footer vary run to run"
    fix: "Require subject line matching ^(feat|fix|refactor|chore)(\\([^)]+\\))?: .{1,72}$"

  - id: D7
    location: "Step 7, PR body format"
    axis: constrain
    severity: medium
    effort: S
    nondeterminism: "PR body template described as English bullet list; structure and section names vary"
    fix: "Pin required markdown headings: ## Summary, ## Ticket, ## Testing in that order"

  - id: D8
    location: "Step 9, commit and file counts in summary"
    axis: offload
    severity: low
    effort: S
    nondeterminism: "<count> placeholders filled from model memory; may be wrong if commits were added late"
    fix: "git rev-list --count main..HEAD; git diff --stat main..HEAD | tail -1"
```

---

### Assertions → `skills/finish-feature/determinism.promptfooconfig.yaml`

Axis B findings D4, D6, D7, D8 produce output assertions. Config written to disk (content below). **Note:** `finish-feature` modifies git state and requires a real worktree fixture; the provider uses a read-only dry-run mode (`--print` with a controlled fixture branch). Axis A fixes (D1, D2, D3, D5) produce bats tests marked "apply after refactor".

```yaml
# skills/finish-feature/determinism.promptfooconfig.yaml
# Run: npx -y promptfoo@latest eval -c determinism.promptfooconfig.yaml
# Fixture: a git repo at /tmp/devflow-fixture on branch feat/TEST-123 with one commit ahead of main.
# Set: DEVFLOW_FIXTURE=/tmp/devflow-fixture before running.
description: finish-feature determinism assertions

prompts:
  - '{{input}}'

providers:
  - id: 'exec: bash run-skill.sh'
    label: finish-feature@head

tests:
  # D7: PR body must contain pinned section headings, no free prose blob
  - description: "D7 — PR body contains required section headings"
    vars:
      input: '/devflow:finish-feature'
    assert:
      - type: icontains
        value: '## Summary'
      - type: icontains
        value: '## Ticket'
      - type: icontains
        value: '## Testing'

  # D4: Review gate findings must appear as a table, not free prose
  - description: "D4 — review gate findings use table format"
    vars:
      input: '/devflow:finish-feature'
    assert:
      - type: regex
        value: '\| Finding \| Severity \| Source \|'
      - type: not-icontains
        value: 'I found the following issues'   # prose preamble smell

  # D8: Commit count in summary is a bare integer, not narrated
  - description: "D8 — Commits count is a digit in the Feature Complete block"
    vars:
      input: '/devflow:finish-feature'
    assert:
      - type: regex
        value: '\*\*Commits:\*\* \d+'
      - type: regex
        value: '\*\*Files changed:\*\* \d+'

  # D6: Subject line of generated commit matches conventional commits pattern
  - description: "D6 — commit message subject follows conventional commits"
    vars:
      input: '/devflow:finish-feature'
    assert:
      - type: regex
        value: '^(feat|fix|refactor|chore|test|docs)(\([^)]+\))?: .{1,72}'

  # Axis B — no raw markdown fences in the Feature Complete block
  - description: "no fenced code blocks in Feature Complete summary"
    vars:
      input: '/devflow:finish-feature'
    assert:
      - type: not-icontains
        value: '```'
```

**Bats tests (Axis A — apply after refactor):**

```bash
# tests/unit/finish-feature.bats  (apply after D1/D2/D5 extract functions)

@test "extract_ticket: feature branch" {
  run bash -c 'echo "feat/MES-123-foo" | grep -oE "[A-Z]+-[0-9]+" || echo none'
  [ "$output" = "MES-123" ]
}

@test "extract_ticket: no ticket in branch" {
  run bash -c 'echo "refactor-cleanup" | grep -oE "[A-Z]+-[0-9]+" || echo none'
  [ "$output" = "none" ]
}

@test "branch_guard: blocks main" {
  BRANCH=main
  run bash -c 'case "$BRANCH" in main|master) echo BLOCKED; exit 1;; esac; echo OK'
  [ "$status" -eq 1 ]
  [ "$output" = "BLOCKED" ]
}

@test "branch_guard: allows feature branch" {
  BRANCH=feat/MES-123-foo
  run bash -c 'case "$BRANCH" in main|master) echo BLOCKED; exit 1;; esac; echo OK'
  [ "$output" = "OK" ]
}

@test "todo_grep: finds FIXME in diff" {
  run bash -c 'printf "+  // FIXME: remove this\n+  const x = 1;\n" | grep -E "^\+.*(TODO|FIXME)"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIXME"* ]]
}

@test "todo_grep: ignores removals" {
  run bash -c 'printf "-  // FIXME: old\n+  const x = 1;\n" | grep -E "^\+.*(TODO|FIXME)"'
  [ "$status" -eq 1 ]
}
```

---

### ROI

Top fix: **D2** (severity=high, effort=S) — the English branch guard is the only finding where a wrong model read can silently ship commits to `main`.

Order: **D2** > D1 > D5 > D7 > D4 > D3 > D8 > D6

- D2 and D1 are both single-line bash replacements; do them together.
- D5 (TODO grep) closes a silent hole in the deferral gate — the gate exists precisely to catch deferrals, so an instructional grep that the model might skip defeats the whole mechanism.
- D7 (PR body) is the highest-value Axis B fix: PRs are the external artifact and their format is currently fully free-form.
- D4, D3 are M-effort or need subagent protocol changes.
- D6 and D8 are cosmetic; fix last.
