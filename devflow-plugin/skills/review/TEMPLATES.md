# Review templates — scoring, output, and VCS draft API

Bundle file referenced by `SKILL.md` Phases 3 (scoring), 4 (output), and 5 (draft inline review).

## Phase 3 — Confidence scoring rubric

Score every finding 0–100. Drop anything below 50.

| Score | Meaning | Action |
|-------|---------|--------|
| 0–24 | False positive / linter territory / pre-existing | Drop |
| 25–49 | Low impact, or stylistic without guideline backing | Drop |
| 50–74 | Real but minor, pre-existing pattern, nitpick | Mention as **Suggestion** |
| 75–89 | Very likely real, important, will impact functionality | Report as **Important** |
| 90–100 | Confirmed real, critical, production risk | Report as **Critical** |

**Pre-existing pattern rule:** if the same pattern exists in other (untouched) files in the codebase (verify with `Grep`/`Glob`), cap the finding's confidence at 50. Acknowledge but don't block — that's a separate refactor.

**Deduplication:** when multiple agents flag the same `file:line` for the same root cause, keep the highest-confidence version and append `(flagged by N/<active_agents> agents)` for added weight.

**Cross-check against merged sibling MRs (Source-of-Truth):** before finalizing a finding, sanity-check it against the actual code in merged sibling MRs from Phase 1d. If sibling-MR code disagrees with what a doc or ticket says, follow the sibling MR — it's the absolute SoT.

## Phase 4 — Output template

```
# Code Review: <PR/MR title or "Local diff">

**Source:** <URL or "local working tree">  •  **Mode:** <quick|thorough>  •  **Files changed:** <N>
**Verdict:** READY TO MERGE / NEEDS FIXES / NEEDS DISCUSSION

## Context used
- Task: <task ID and title, or "none">
- Epic: <epic ID and title, or "none">
- Documents: <N fetched, or "none">
- Sibling MRs: <N, or "none">
- Conventions: <CLAUDE.md found: yes/no>
- Memory: <Hindsight results: N, or "skipped">
- Agents run: <list of active agents>

## Strengths
- <what the author did well>

## Critical (must fix before merge)
### <file>:<line> — <one-sentence what>
**Confidence:** <N>/100  •  **Agent(s):** <names>  •  **Flagged by:** <N>/<active_agents>
<why it matters>

**Suggested fix:**
\`\`\`<lang>
<diff or replacement>
\`\`\`

## Important (should fix)
<same shape>

## Suggestions (consider)
- <one-liner with file:line>

---
**Rationale:** <one or two lines justifying the verdict>
```

Skip empty sections. For Quick mode, drop the per-finding confidence numbers and combine findings into one summary block.

## Phase 5 — Draft inline review on the MR

### GitHub — create a PENDING review

Omit the `event` field so the review stays in PENDING state; the user submits manually from the GitHub UI.

```bash
gh api --method POST repos/<owner>/<repo>/pulls/<n>/reviews \
  --input - <<EOF
{
  "commit_id": "<head_sha>",
  "comments": [
    { "path": "src/file.ts", "line": 42, "side": "RIGHT", "body": "<comment body>" }
  ]
}
EOF
```

### GitLab — draft notes (per-comment)

GitLab requires `diff_refs` for inline positioning. Fetch once, then post each comment as a draft note.

```bash
diff_refs=$(glab api "projects/:fullpath/merge_requests/<id>" \
  --jq '.diff_refs | {base_sha, head_sha, start_sha}')

glab api --method POST "projects/:fullpath/merge_requests/<id>/draft_notes" \
  -f note="<comment body>" \
  -f "position[position_type]=text" \
  -f "position[base_sha]=<base_sha>" \
  -f "position[head_sha]=<head_sha>" \
  -f "position[start_sha]=<start_sha>" \
  -f "position[old_path]=src/file.ts" \
  -f "position[new_path]=src/file.ts" \
  -f "position[new_line]=42"
```

### Comment body template

```markdown
**[<Agent>]** | Severity: <level> | Confidence: <N>/100

<what>

**Why it matters:** <why>

**Suggested fix:**
\`\`\`suggestion
<code>
\`\`\`
```

After drafting: confirm to the user that the review is in PENDING state — they need to open the MR/PR UI and click "Submit review" to actually send it.
