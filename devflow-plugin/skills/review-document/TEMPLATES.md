# Review templates — scoring + output

Bundle file referenced by `SKILL.md` Phase 3 (scoring + cross-check) and Phase 4 (visual output).

## Phase 3 — Confidence scoring rubric

Score every finding 0–100. Drop anything below 50.

| Score | Meaning | Section in output |
|---|---|---|
| 0–49 | Linter territory / styling / false positive / pre-existing minor drift | Drop |
| 50–74 | Real but minor, low-impact, or recurring-but-already-flagged-once | 🟡 **Suggestion** |
| 75–89 | Likely real, impacts comprehension or correctness for the declared audience | 🟠 **Important** |
| 90–100 | Confirmed real, critical, must-fix before publish (self-contradiction, factual error, missing-from-Meta-docs claim) | 🔴 **Critical** |

### Recurring-pattern cap
Same issue class at >3 anchors → collapse to one finding with `category: "recurring"` and list affected anchors in `detail`. Do not emit per-instance findings for recurring patterns.

### Cross-agent dedup
Same anchor + same issue class flagged by multiple agents → keep the highest-confidence version, append `(N/<active> agents)` to the title.

### Cross-check status (mandatory on every finding — set in Phase 3b)

| Status | Meaning | Output treatment |
|---|---|---|
| **NEW** | No prior comment overlaps anchor + issue class | Include in 🔴 / 🟠 / 🟡 section as normal |
| **RAISED-OPEN** | Existing comment covers this; still unresolved | Include in section + line tag `(also raised by @<user> — open)` |
| **RAISED-RESOLVED-FIXED** | Existing comment covers this AND latest doc text confirms fix | **DO NOT re-flag.** Move to 🟢 Strengths under "Already addressed in review comments" with comment author |
| **RAISED-RESOLVED-NOT-FIXED** | Resolved by author but issue still present in current text | Include in section + tag `(thread marked resolved but issue still present)` — high reviewer-trust value |

Re-flagging closed comments erodes trust. The cross-check is the single biggest source of review-noise reduction.

---

## Phase 4 — Visual output template

Compact, emoji-anchored, ADHD-friendly. ~3 lines per finding in 🔴/🟠, one line in 🟡. Bold the **key term** in each finding title (bionic-reading anchor). TL;DR block at the bottom with severity counts + top-3 fixes + one-line verdict.

### Emoji legend (used at every section header AND every finding bullet)

| Emoji | Means |
|---|---|
| 🔴 | Critical (must fix before publish) |
| 🟠 | Important (should fix) |
| 🟡 | Suggestion (consider) |
| 🟢 | Strength / already-addressed-in-comments |
| 🔵 | Info / context / TL;DR |

### Template

```
# 🔵 Doc Review: <doc title>

**Source:** <URL or local path>  •  **Type:** <kb|spike|rfc|runbook|prd|design|generic>  •  **Mode:** <quick|thorough>  •  **Length:** <N words>
**Verdict:** ✅ APPROVED / ⚠️ NEEDS FIXES / ❓ NEEDS DISCUSSION

## 🔵 Context used
- 🎯 **Initiative:** <Jira/Linear ID + title or "none">
- 📚 **Audience:** <detected audience — customer / engineer / sales / mixed>
- 🔍 **Verified vs external sources:** <N upstream docs fetched or "none">
- 💬 **Existing platform comments:** <N total / N resolved / N open / "skipped — no platform API">
- 🧠 **Hindsight memory:** <N hits or "skipped">
- 🤖 **Agents run:** <comma-separated list>
- 🧹 **Cleanup:** <"stripped N strikethrough spans" / "raw fetch used">

## 🟢 Strengths

- 🟢 <one-liner — what the author did well>
- 🟢 **Already addressed in review comments:** <N issues raised by @<users> + resolved> (no re-flag)

## 🔴 Critical (must fix before publish)

### 🔴 <ANCHOR> — **<key term>** <one-sentence what>
**Conf:** <N>/100 • **Agent(s):** <names> • **Status:** NEW / RAISED-OPEN @<user>
Quote: `"<verbatim snippet>"`
**Why:** <one sentence — why this matters>
**Fix:**
\`\`\`
<inline rewrite, verbatim>
\`\`\`

## 🟠 Important (should fix)

### 🟠 <ANCHOR> — **<key term>** <what>
**Conf:** <N>/100 • **Status:** <NEW | RAISED-OPEN | RAISED-RESOLVED-NOT-FIXED>
Quote: `"<verbatim>"`
**Why:** <one sentence>
**Fix:** <inline 1-liner OR fenced rewrite>

## 🟡 Suggestions

- 🟡 <ANCHOR> — **<key term>**: `"<short quote>"` → `"<short rewrite>"` (why: <half-sentence>)

---

## 🔵 Missing sections (add before publish)

1. **<section name>** — <why it's missing + what to cover>

## 🔵 TL;DR

> 🔴 **<N> critical** · 🟠 **<N> important** · 🟡 **<N> suggestions** · 🟢 **<N> already-addressed**
>
> **Top 3 to fix:**
> 1. **<finding title>** — `<ANCHOR>`
> 2. **<finding title>** — `<ANCHOR>`
> 3. **<finding title>** — `<ANCHOR>`
>
> **Verdict:** <one-line justification>
```

### Anchor format rules (auto-picked in Phase 0c)

- **Local file** → `<filepath>:<line>` (e.g. `/Users/foo/docs/spike.md:42`)
- **Hosted doc** (Google Doc / Confluence / arbitrary URL) → `§"<H2/H3 heading>" → "<short verbatim quote>"` so the user can Ctrl+F to the location in the platform UI

### Rules for visual output

- **Skip empty sections.** If no critical findings, drop the 🔴 Critical heading entirely. Do NOT print "None".
- **Bold the key term** in each finding title (the noun phrase that names the issue class — "self-contradiction", "missing 30-day rule", "phantom UI string"). Bionic-reading anchor.
- **3 lines max per finding** in 🔴/🟠. One line for 🟡.
- **Cross-check status is mandatory** on every finding (NEW / RAISED-OPEN / RAISED-RESOLVED-FIXED / RAISED-RESOLVED-NOT-FIXED). RAISED-RESOLVED-FIXED items go to 🟢, never appear in 🔴/🟠/🟡.
- **Anchor format must match `ANCHOR_TYPE` set in Phase 0c.** Never emit `file:line` for a Google Doc / Confluence page.
- **TL;DR mandatory.** Severity counts + top-3 + one-line verdict.
- **Quick mode** drops the per-finding `Conf:` line and `Fix:` fenced blocks; consolidates into one paragraph per severity.

### Rules for the prose-rewrite Fix block

For prose findings, the `Fix:` block contains the rewritten sentence verbatim (NOT a code-suggestion `suggestion` fence — that is for diff inline-comments which we do not emit). The user copies the rewrite into the source platform manually.

Example:
```
**Fix:**
\`\`\`
No. Aircall does not currently support WhatsApp voice calls. Separately, traditional outbound phone calls require a phone number, which is unavailable for username-only contacts.
\`\`\`
```

For one-line suggestions, inline the rewrite directly:
```
**Fix:** Drop the duplicate "Aircall" — change `"in the Aircallin Aircall workspace"` to `"in Aircall Workspace"`.
```
