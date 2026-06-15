# Review templates — scoring, output, and VCS draft API

Bundle file referenced by `SKILL.md` Phases 3 (scoring + cross-check), 4 (visual output), and 5 (draft inline review).

## Phase 3 — Confidence scoring + dedup + cross-check status

### Scoring rubric

Score every finding 0–100. Drop anything below 50.

| Score | Meaning | Action |
|---|---|---|
| 0–49 | False positive / linter territory / pre-existing / nitpick without guideline backing | Drop |
| 50–74 | Real but minor, pre-existing pattern | 🟡 **Suggestion** |
| 75–89 | Very likely real, important, impacts functionality | 🟠 **Important** |
| 90–100 | Confirmed real, critical, production risk | 🔴 **Critical** |

**Pre-existing pattern cap:** if the same pattern exists in untouched files (verify with `Grep`/`Glob`), cap confidence at 50. Acknowledge but don't block.

**Cross-agent dedup:** when multiple agents flag the same `file:line` for the same root cause, keep the highest-confidence version and append `(N/<active> agents)`.

**Sibling-MR Source-of-Truth cross-check:** before finalizing, sanity-check against merged sibling-MR code. If sibling MRs disagree with docs/tickets, follow the sibling MRs.

### Cross-check status (NEW — applied to every finding from Phase 1e)

| Status | Meaning | Output treatment |
|---|---|---|
| **NEW** | No prior thread mentions this file:line or issue class | Include in 🔴 / 🟠 / 🟡 section as normal |
| **RAISED-OPEN** | Existing thread covers this; still unresolved | Include ONLY if you add new signal the thread is missing (evidence it lacked, a consequence it overlooked, a concrete fix). If you'd just be echoing or `+1`-ing it, SKIP (don't pile on). When kept, lead with the new signal and tag `(builds on @<user>'s thread #N, open)` |
| **RAISED-RESOLVED-FIXED** | Existing thread covers this AND latest diff confirms fix landed | **DO NOT re-flag.** Add to 🟢 Strengths under "Already addressed in review" with thread # + fix SHA |
| **RAISED-RESOLVED-NOT-FIXED** | Resolved by author but issue still present at HEAD | Include in section + line tag `(thread #N marked resolved but issue still present)` — high reviewer-trust value |

Re-flagging closed issues erodes trust. The cross-check is the single biggest source of review-noise reduction.

---

## Phase 4 — Visual output template

Compact, emoji-anchored, ADHD-friendly. ~3 lines per finding. Bold the key term in each finding (bionic-reading-style emphasis). TL;DR at the bottom with severity counts + top 3 fixes.

### Emoji legend (used at every section header AND every finding bullet)

| Emoji | Means |
|---|---|
| 🔴 | Critical (must fix before merge) |
| 🟠 | Important (should fix) |
| 🟡 | Suggestion (consider) |
| 🟢 | Strength / already-fixed / passing check |
| 🔵 | Info / context / TL;DR |

### Template

```
# 🔵 Code Review: <PR/MR title or "Local diff">

**Source:** <URL or "local working tree">  •  **Mode:** <quick|thorough>  •  **Files changed:** <N>  •  **Diff:** <N lines>
**Verdict:** ✅ READY TO MERGE / ⚠️ NEEDS FIXES / ❓ NEEDS DISCUSSION

## 🔵 Context used
- 🎯 **Task:** <task ID + title or "none">
- 🧩 **Epic:** <epic ID or "none">
- 📄 **Docs:** <N fetched>
- 🔁 **Sibling MRs:** <N>
- 📜 **Conventions:** CLAUDE.md <found / not found>
- 🧠 **Memory:** <N Hindsight hits>
- 💬 **Existing discussions:** <N threads / N resolved>
- 🤖 **Agents run:** <list>

## 🟢 Strengths

- 🟢 <what the author did well — one line each>
- 🟢 **Already addressed in review:** <N issues raised by reviewers/bots + fixed in commits <sha-list>> (no re-flag)

## 🔴 Critical (must fix before merge)

### 🔴 <file>:<line> — **<key term>** <one-sentence what>
**Conf:** <N>/100 • **Agent(s):** <names> • **Status:** NEW / RAISED-OPEN @<user> #<N>
<why it matters — 1 sentence>

**Fix:**
\`\`\`<lang>
<diff or replacement>
\`\`\`

**Comment** (paste-ready, teammate voice, em-dash-free):
> <this finding rewritten as a real reviewer note: lowercase, hedged, lead with the observation then the why, cite `file:line`. No severity / Conf / agent labels.>

## 🟠 Important (should fix)

### 🟠 <file>:<line> — **<key term>** <what>
**Conf:** <N>/100 • **Scope:** in-diff • **Status:** <NEW / RAISED-OPEN / RAISED-RESOLVED-NOT-FIXED>
<why — 1 sentence>

**Fix:** <inline 1-line fix OR fenced block>

**Comment** (paste-ready, teammate voice, em-dash-free):
> <same finding written as a reviewer note: lowercase, hedged, cite `file:line`. No severity / Conf / agent labels.>

### 🟠 📄 <file>:<line> — **<key term>** <what> _(external — cannot post inline)_
**Conf:** <N>/100 • **Scope:** external-unmodified • **Anchor:** `<external_anchor_file>` • **Status:** <NEW / RAISED-OPEN>
<why — 1 sentence; underlying issue is in `<external_anchor_file>`, NOT changed by this MR>

**Fix:** <how to address — usually "open a separate ticket / refactor PR for `<external_anchor_file>`" or a fix that can be made inline in the diff site>

## 🟡 Suggestions

- 🟡 `<file>:<line>` — **<key term>** <one-liner with the fix inline>
- 🟡 📄 `<file>:<line>` — **<key term>** <one-liner> _(external — anchor: `<external_anchor_file>`)_

---

## 🔵 TL;DR

> 🔴 **<N> critical** · 🟠 **<N> important** · 🟡 **<N> suggestions** · 🟢 **<N> already-fixed**
>
> **Top 3 to fix:**
> 1. **<finding 1>** — `<file>:<line>`
> 2. **<finding 2>** — `<file>:<line>`
> 3. **<finding 3>** — `<file>:<line>`
>
> **Verdict:** <one-line justification>
```

### Rules for the visual output

- **Skip empty sections.** If no critical findings, drop the 🔴 Critical heading entirely (don't print "None").
- **Bold the key term** in each finding's title (the noun phrase that names the bug class — "duplicate metric emission", "type assertion", "naming inconsistency"). This is the bionic-reading anchor.
- **3 lines max per finding** in 🔴 / 🟠. One line each in 🟡.
- **Every 🔴 / 🟠 finding ends with a `**Comment**` block:** the same finding rewritten in the teammate voice (see "Comment body voice"), em-dash-free and paste-ready, shown as a `>` blockquote AFTER the normal structured finding. It is the exact text the user can copy into the MR even when they don't draft inline. 🟡 Suggestions are short enough to write directly in that voice. Skip the Comment block in Quick mode.
- **Cross-check status is mandatory** on every finding (NEW / RAISED-OPEN / RAISED-RESOLVED-FIXED / RAISED-RESOLVED-NOT-FIXED). RAISED-RESOLVED-FIXED items move to 🟢 Strengths, never appear in 🔴/🟠/🟡.
- **`scope` is mandatory** on every finding. Findings with `scope=external-unmodified` MUST be prefixed with 📄 and tagged "_(external — cannot post inline)_". `external_anchor_file` MUST be populated.
- **TL;DR is mandatory.** Counts per severity + top 3 fixes + one-line verdict. The 📄 count is shown separately as "external-only".
- **Quick mode** drops the per-finding `Conf:` line and `Fix:` code blocks; consolidates into one paragraph per severity.
- **Spec mode** replaces the verdict pillars: instead of "READY TO MERGE / NEEDS FIXES / NEEDS DISCUSSION", use "APPROVED / ISSUES FOUND / NEEDS DISCUSSION". Categories change too: 🟠 Important → "Issues" (completeness/consistency/clarity blockers); 🟡 Suggestions → "Advisory" (YAGNI nits, polish). Score gate from Tessl (if SKILL.md): note current score in Context, flag if < 85% (below create-skill's quality gate).

---

## Phase 5 — Draft inline review on the MR

### GitHub — PENDING review (omit `event`)

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

### Comment body voice (write like a teammate, not a bot)

Inline MR/PR comments are NOT the structured chat output. For the posted comment, DROP the `**[Agent]** | Severity | Confidence` header, the `**Why it matters:** / **Suggested fix:**` scaffolding, and the emoji severity tags. That scaffolding is the dead giveaway of AI text and erodes reviewer trust. Write each note the way a real teammate leaves a small, helpful comment:

- **Lowercase, conversational, hedged** as a question or soft suggestion: "would it make sense to…", "might be worth…", "should we…?", "i think…", "not for this MR but…". Slang like `wdyt` / `yh` / `dw` is good.
- **Lead with the observation, then the why in the same breath.** One short paragraph for most; a second only when there's a real consequence to explain. Cite code inline with backticks: `file.ts:line`.
- **Collaborative framing:** "we", "future us", "before we merge". Leave the call to the author ("i'll leave it to your discretion").
- **A light `:)` / `:))` sparingly is fine.** Don't force it.
- **NEVER use em dashes (`—`).** Use a comma, a period, parentheses, or "since" / "so" instead. Hard rule.
- **Suggest, never command.** No "must fix", no severity labels, no confidence numbers in the posted comment. Severity lives in the chat summary, not the inline note.

Good (reads human):
> might be worth checking this against the failure metrics we already emit first. `receiveMessageSyncCommandValidator.ts:40` already emits a failure metric right before it throws, and that throw lands here, so native twilio/bandwidth/legos would bump two metrics. wdyt about reusing `addMetricFor*Messaging` or adding a tag here?

Bad (reads as AI, do NOT post this):
> 🟠 **[bug-scanner]** | Severity: Important | Confidence: 85/100
> **Why it matters:** duplicate metric emission. **Suggested fix:** …

Use a fenced `suggestion` block only when it's a clean one-line replacement the author can click-apply; otherwise plain prose reads more naturally.

After drafting: confirm to the user the review is in PENDING state, and that they submit it manually from the VCS UI.

### ⚠️ Inline drafting MUST skip `scope=external-unmodified` findings

GitHub and GitLab both require inline review comments to be on a changed line in the MR's diff. A finding whose underlying issue lives in an unmodified file CANNOT be drafted as an inline comment — the API will reject it. When drafting:

1. Filter findings to `scope == "in-diff"` only.
2. Tell the user in the confirmation: "Drafted N inline comments. M findings were external-unmodified and could NOT be drafted — see the chat output for those (consider opening a separate ticket or follow-up MR for the anchor files: `<list>`)."
3. Never silently drop external findings without telling the user.
