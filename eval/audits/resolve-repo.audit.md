## Determinism Audit: resolve-repo

### Findings

| ID | Location | Axis | Severity | Effort | Nondeterminism | Deterministic fix |
|----|----------|------|----------|--------|----------------|-------------------|
| D1 | Step 1, VCS platform detect | offload | high | S | English prose classification: "`github.com` → `github`, `gitlab.com` or `gitlab.` → `gitlab`" — model infers mapping, drifts on self-hosted hosts like `gitlab.acme.io` | `case` statement on the extracted hostname: `*github.com*) echo github;;` `*gitlab.*) echo gitlab;;` |
| D2 | Step 1, group/subgroup extract | offload | high | S | "Use the **most specific common group**" — model judges what counts as "most specific" with no rule | Compute longest common prefix of all parsed group paths in bash; no judgment needed |
| D3 | Step 2, ticket ID prefix match | offload | medium | S | "`MES` in `MES-3716` → match against repos containing 'mes' or 'messaging'" — hardcoded mapping inside prose, will hallucinate for unfamiliar prefixes | Extract prefix with `grep -oE '^[A-Z]+'` then do case-insensitive substring match against repo names; no hand-coded synonym list |
| D4 | Step 2, scoring thresholds | offload | high | M | "scores HIGH (clear winner)" / "no confident match" — model decides score band with no numeric rule | Define integer score (prefix-match=10, label-match=5, keyword-match=1 per word); HIGH ≥ 10, MEDIUM 5-9, LOW < 5; hardcode cutoffs |
| D5 | Step 2, stop-word filter | offload | low | S | "Ignore stop words" with no stop-word list provided — model decides which words to drop | Ship a fixed stop-word list inline: `the|a|an|for|in|on|of|to|and|or|with|is|are|…` and strip with `sed -E "s/\\b(the\|a\|...)\\b//g"` |
| D6 | Step 4, result block format | constrain | high | S | "Repo Match Results" block has no pinned schema — headers, list items, and labels (`HIGH:`, `[LOCAL]`) can vary across runs | Pin the exact format and add "output ONLY the block with no prose, no fences, no extra commentary" |
| D7 | Step 4, ranking/ordering | offload | medium | S | "Score and present a concise ranked list" — sort order and tie-breaking unstated | Sort descending by integer score (D4); tie-break alphabetically by repo name |
| D8 | Step 5, setup-hints detection | offload | low | S | "Report setup hints" — model infers which hints to show | Already uses explicit `[ -f ... ]` guards in the shell block; the nondeterminism is the prose instruction "report setup hints" without pointing to that block — point to it explicitly |
| D9 | Step 6, return block format | constrain | high | S | "Resolved Repository" block: fields listed but no schema enforcement — model may add prose, reorder fields, omit Cloned/Setup fields when "obvious" | Pin exact field order + add "output ONLY this block, no leading prose, no trailing commentary, no markdown fences" |

---

### Findings (machine-readable)

```yaml
skill: resolve-repo
findings:
  - id: D1
    location: "step 1, VCS platform detect"
    axis: offload
    severity: high
    effort: S
    nondeterminism: "English prose classification of remote URL hostname to VCS platform name; self-hosted hosts cause hallucination"
    fix: "case statement: *github.com*) echo github;; *gitlab.*) echo gitlab;; *bitbucket.*) echo bitbucket;; *dev.azure.*) echo azure;; *) echo unknown;;"

  - id: D2
    location: "step 1, group/subgroup extraction"
    axis: offload
    severity: high
    effort: S
    nondeterminism: "'Most specific common group' decided by model judgment with no algorithm"
    fix: "Compute longest common path-prefix across all parsed group strings in bash; strip trailing slash"

  - id: D3
    location: "step 2, ticket ID prefix extraction"
    axis: offload
    severity: medium
    effort: S
    nondeterminism: "Model hand-maps ticket prefix 'MES' to synonym 'messaging' with no rule; breaks for unknown prefixes"
    fix: "grep -oE '^[A-Z]+' on TICKET_ID; case-insensitive substring match of prefix against repo names — no synonym expansion"

  - id: D4
    location: "step 2, scoring thresholds"
    axis: offload
    severity: high
    effort: M
    nondeterminism: "'Clear winner' / 'confident match' decided by model feel with no numeric rule"
    fix: "Integer score: prefix-match=10, label-match=5, keyword-match=1 per word; HIGH>=10, MEDIUM 5-9, LOW<5"

  - id: D5
    location: "step 2, stop-word filter"
    axis: offload
    severity: low
    effort: S
    nondeterminism: "'Ignore stop words' with no list; model decides what to drop"
    fix: "Inline fixed stop-word regex: the|a|an|for|in|on|of|to|and|or|with|is|are|fix|add|update|support"

  - id: D6
    location: "step 4, Repo Match Results block"
    axis: constrain
    severity: high
    effort: S
    nondeterminism: "Headers, list-item format, and score labels (HIGH/MEDIUM/LOW) vary across runs; no schema enforced"
    fix: "Pin exact format; instruct 'output ONLY this block, no prose, no fences, no extra fields'"

  - id: D7
    location: "step 4, ranking order"
    axis: offload
    severity: medium
    effort: S
    nondeterminism: "Tie-breaking order unstated; model chooses arbitrarily"
    fix: "Sort descending by integer score; tie-break alphabetically by repo name"

  - id: D8
    location: "step 5, setup hints"
    axis: offload
    severity: low
    effort: S
    nondeterminism: "Prose says 'report setup hints' without pointing to the shell block that already implements it correctly"
    fix: "Replace prose with explicit reference to the shell block; no model judgment needed"

  - id: D9
    location: "step 6, Resolved Repository block"
    axis: constrain
    severity: high
    effort: S
    nondeterminism: "Field order and presence not enforced; model may omit Cloned/Setup fields or add prose"
    fix: "Pin exact field order; add 'output ONLY this block, no leading/trailing prose, no markdown fences'"
```

---

### Assertions → `skills/resolve-repo/determinism.promptfooconfig.yaml`

9 findings → 4 promptfoo assertions (Axis B: D6, D9) + 5 bats stubs (Axis A: D1–D5, D7; apply after refactor).

---

### `skills/resolve-repo/determinism.promptfooconfig.yaml`

```yaml
description: resolve-repo determinism assertions
prompts: ['{{input}}']
providers:
  - id: 'exec: bash eval/lib/run-skill.sh'
    label: resolve-repo@head
tests:
  # D9: step 6 return block — no fences, required fields present
  - description: "D9 - Resolved Repository block has no markdown fences"
    vars:
      input: '/devflow:resolve-repo WORKSPACE_DIR=~/dev/aircall TICKET_ID=MES-3716 TICKET_TITLE="Fix messaging webhook retry"'
    assert:
      - type: not-icontains
        value: '```'
      - type: regex
        value: '\*\*Repo:\*\*\s+\S+'
      - type: regex
        value: '\*\*VCS Platform:\*\*\s+(github|gitlab|bitbucket|azure|unknown)'
      - type: regex
        value: '\*\*Cloned:\*\*\s+(yes|no)'

  # D6: step 4 Repo Match Results block — score labels are pinned values
  - description: "D6 - Repo Match Results score labels are HIGH/MEDIUM/LOW only"
    vars:
      input: '/devflow:resolve-repo WORKSPACE_DIR=~/dev/aircall TICKET_ID=MES-3716 TICKET_TITLE="Fix messaging webhook retry"'
    assert:
      - type: not-icontains
        value: '```'
      - type: regex
        value: '(HIGH|MEDIUM|LOW):'
      - type: regex
        value: '\[(LOCAL|REMOTE)\]'

  # D1+D2: platform and group extraction — only allowed values
  - description: "D1 - VCS Platform value is one of the allowed enum values"
    vars:
      input: '/devflow:resolve-repo WORKSPACE_DIR=~/dev/aircall TICKET_ID=MES-3716 TICKET_TITLE="Fix messaging webhook retry"'
    assert:
      - type: regex
        value: '\*\*VCS Platform:\*\*\s+(github|gitlab|bitbucket|azure|unknown)\b'

  # D4: no prose qualifying the score band (model must not emit "probably HIGH" etc.)
  - description: "D4 - Score bands are bare HIGH/MEDIUM/LOW without qualifying prose"
    vars:
      input: '/devflow:resolve-repo WORKSPACE_DIR=~/dev/aircall TICKET_ID=MES-3716 TICKET_TITLE="Fix messaging webhook retry"'
    assert:
      - type: not-icontains
        value: 'probably'
      - type: not-icontains
        value: 'likely'
      - type: not-icontains
        value: 'confident'
```

---

### Bats stubs (Axis A — apply after refactor)

```bash
# tests/unit/resolve_repo.bats — apply after lib/resolve_repo.sh extracts these functions

@test "detect_vcs: github HTTPS" {
  run detect_vcs "https://github.com/org/repo.git"
  [ "$output" = "github" ]
}
@test "detect_vcs: gitlab HTTPS" {
  run detect_vcs "https://gitlab.com/g/repo.git"
  [ "$output" = "gitlab" ]
}
@test "detect_vcs: self-hosted gitlab" {
  run detect_vcs "https://gitlab.acme.io/g/repo.git"
  [ "$output" = "gitlab" ]
}
@test "detect_vcs: unknown host" {
  run detect_vcs "https://bitbucket.org/org/repo.git"
  [ "$output" = "bitbucket" ]
}

@test "score_repo: prefix match scores 10" {
  run score_repo "messaging" "" "MES" "" ""
  [ "$output" -ge 10 ]
}
@test "score_repo: no match scores 0" {
  run score_repo "unrelated-tool" "" "MES" "" ""
  [ "$output" -eq 0 ]
}

@test "extract_ticket_prefix: standard ID" {
  run extract_ticket_prefix "MES-3716"
  [ "$output" = "MES" ]
}
@test "extract_ticket_prefix: numeric only" {
  run extract_ticket_prefix "123"
  [ "$output" = "" ]
}
```

---

### ROI

Top fix: **D1** (severity=high, effort=S) — VCS platform misdetect cascades to wrong CLI tool for all remote calls; one `case` statement fixes it.

Order: **D1 > D9 > D6 > D4 > D2 > D3 > D7 > D5 > D8**

- D1/D9/D6: high severity + S effort — do these first
- D4: high severity but M effort (needs scoring wiring)
- D2/D3/D7: medium severity, S effort
- D5/D8: low severity, S effort
