---
name: readable-doc
description: Use when writing or reformatting a plan, spike, design, or implementation doc that will be reviewed in plannotator (or any markdown reviewer) for a reader who wants fast, scannable, ADHD-friendly structure. Produces plain-language TLDR-first docs with a verified plannotator-safe formatting toolkit (status circles, GFM-alert callouts, Unicode underline and small-caps for emphasis, compact emoji-column tables, collapsible text detail, a considered-but-rejected section, and two mandated diagrams, namely a base how-it-works diagram plus a colour-coded current-vs-options diagram).
---

# Readable Doc

**You are a documentation designer for a reader with ADHD** who reviews in plannotator and skims before they read. You have watched dense, correct docs get bounced purely because they were a wall of text. You make the *structure* carry the meaning: the reader gets the decision from the plain-language TLDR and the diagrams alone, then drills only where they choose.

**Core principle:** every formatting choice is an empirical fact about the renderer, not a guess. This skill ships the verified plannotator matrix so you never re-fail the same way. If the renderer version changes, re-probe (see `verify-first`) before trusting it.

> [!IMPORTANT]
> This skill is the *structure and formatting layer*, not the content. Use `write-spike`, `spec-feature`, `writing-plans` for what the doc says.

## When to Use

- Writing a spike / design / implementation-plan doc destined for plannotator review.
- Reformatting a doc a reviewer called "a wall of text", "hard to scan", or "not readable".
- Any time you were about to reach for `<u>`, coloured text, or a dense multi-column table in a reviewed markdown doc.

## Verified plannotator matrix (probed 2026-07-14, do not re-guess)

plannotator allows a small tag allowlist and strips the rest.

| Want | ✅ Use this | 🔴 Never (silently fails) |
|---|---|---|
| Callout (top-level) | GFM alerts `> [!NOTE]` `> [!WARNING]` `> [!TIP]` `> [!IMPORTANT]` (real styled boxes) | the same GFM alert inside `<details>` (BREAKS, renders as raw text); coloured `<div>` / HTML boxes |
| Callout inside `<details>` | emoji blockquote + small-caps label: `> 🔴 ʀɪꜱᴋ — ...` (best-rated in-accordion callout) | a GFM alert (breaks in a collapsible) |
| Light aside | emoji blockquote `> 🔴 **Risk:** ...` | — |
| Colour | status emoji 🟢🟠🔴❓ in text and as a table column | text colour via `style` (not applied; a hex shows only a swatch bubble) |
| Diagram / image | plain `![alt](path)` with **NO title attribute** (renders + zooms; absolute or relative, consecutive, in-list all fine) | a **title attribute** `![alt](path "title")` (BREAKS the image, the #1 gotcha), `<img>` (smaller, no zoom), self-link `[![]()]()` (breaks), image inside `<details>` (renders but loses zoom) |
| Collapse minor content | `<details><summary>...</summary> ... </details>` (tables, big tables, and bullet lists all render fine inside) | wrapping images/diagrams in `<details>` (kills zoom); a GFM alert inside (breaks, use an emoji blockquote + small-caps label instead) |
| Table | markdown table, compact, emoji status column (renders fine top-level AND inside `<details>`, even large) | wide walls of text with no status column |
| Bullets | normal markdown `-` lists (leading status emoji ok) | geometric bullets `▸ ◦ ● ◆` on bare lines (collapse to one line) |
| Code / file refs | fenced code block with a language (```` ```ts ````), syntax highlighted | bare inline paths where a highlighted block reads better |

**No em-dashes anywhere** (hard rule): use commas, periods, parentheses, "since"/"so".

## Unicode readability toolkit (verified, use sparingly on SHORT key text)

Markdown has no underline or small-caps and plannotator strips styling HTML, so these effects only survive as Unicode. Generate them with the bundled `textstyle.py`.

| Effect | Helper | Good for |
|---|---|---|
| Underline (single) | `textstyle.py "phrase"` (U+0332) | the key phrase of a bullet |
| Underline (double) | `textstyle.py --double "phrase"` (U+0333) | the ONE most critical phrase in a section |
| ꜱᴍᴀʟʟ ᴄᴀᴘꜱ | `textstyle.py --smallcaps "recommended"` | labels / status tags / verdicts (distinctive) |
| Small caps + underline | `textstyle.py --smallcaps-underline "risk"` | a status label that must pop |
| ~~strikethrough~~ | GFM markdown `~~...~~` | rejected / superseded / done |
| Ordered steps | literal `① ② ③` or `1️⃣ 2️⃣ 3️⃣` | numbered steps inline |

> [!WARNING]
> Unicode combining marks + small-caps break copy/paste, Ctrl-F search, and screen readers. Use ONLY on short KEY phrases and labels, never body text. NEVER underline an identifier / `code` term (the underscores fuse with the underline into a solid blur); wrap identifiers in `` `backticks` `` instead. Reach for markdown `**bold**` / `*italic*` / `` `code` `` first; add Unicode only for underline, small-caps labels, and step numbers.

## Structure rules

1. ① **Plain-language TLDR at the very TOP** (not the end). What / how / why-this-shape / biggest risk / what needs the reader. Status-circle bullets, no jargon (a non-specialist should get the decision). Keep acronyms out of the TLDR or expand them.
2. ② **Status circles everywhere:** 🟢 ok/decided/verified · 🟠 warn/needs-confirm · 🔴 risk/blocker · ❓ open question. First glyph of a bullet, and a table column.
3. ③ **Callouts via GFM alerts** for the few must-not-miss items; emoji blockquotes for lighter asides. 3 to 5 per doc, not more.
4. ④ **Tables stay lean:** max ~4 columns, one idea per cell, emoji status column for colour. Reference-only tables go in `<details>` (kept small).
5. ⑤ **Collapse minor TEXT sections** (evidence, full ledgers, sizing, appendices) in `<details>` so the default view is the decision. Never put diagrams in `<details>` (they lose zoom).
6. ⑥ **Considered-but-rejected section** (mandatory for spikes/plans): options evaluated and dropped, and *why* they were killed (verification ledger, a requirement, a latency probe). Compact fragments, arrows for cause, in the author's voice. This is where a reader checks their idea was not missed.
7. ⑦ **Emphasis:** `**bold**` for key terms; `textstyle.py` (underline / small-caps) for the handful that must pop; `` `code` `` for identifiers/paths.
8. ⑧ **Voice:** compact and scannable, the author's own register (recall from Hindsight / their transcripts). No filler, no em-dashes, warm and direct.
9. ⑨ **Tags + legends:** use ꜱᴍᴀʟʟ ᴄᴀᴘꜱ (via `textstyle.py --smallcaps`) for status tags, verdicts, and section labels (the distinctive tag look the reader wants). Define any abbreviation with a one-line legend the first time it appears; never leave bare `[V]`/`[R]`-style jargon.

## Two mandated diagrams (delegate rendering to `render-diagram`)

Every plan/spike doc gets **both**, rendered as PNGs and embedded as plain top-level images with **absolute paths** (reliable + zoomable):

1. **Base how-it-works** diagram: the flow / architecture as it actually works.
2. **Current-vs-options** decision diagram, colour-coded so the recommendation is obvious:
   - one colour (neutral grey) = **what exists today**,
   - green = the **recommended** option (bold border, ✅ label),
   - red = **rejected** options, each with a one-line kill reason.

> [!TIP]
> Embed as plain `![alt](path)` with **no title attribute** (a `"title"` breaks the image, verified). Absolute or relative both work, consecutive images are fine. Do not wrap in a link, do not use `<img>`, do not put it inside `<details>` (loses zoom). plannotator zoom is built in for plain top-level images.

## plannotator review mechanics

- ❓ **Open in Claude's own in-app browser** (the goal). Reality: plannotator's `--browser <name>` only launches a *native* app (e.g. "Google Chrome"), it cannot target the in-app browser. To view in the in-app browser you must open plannotator's served localhost URL (`PLANNOTATOR_PORT`) with the browser/preview tool. Treat as a follow-up until wired. See `~/.claude/CLAUDE.md` "Plannotator".
- After opening, confirm images loaded. If a top-level image shows a broken icon, it is usually a transient/relative-path issue: use an absolute path and it renders reliably.
- Treat any new formatting trick as a `[B]` claim: probe it in a throwaway doc first. The matrix above is what survived probing; a renderer upgrade can change it.

## Few-shot: before → after

**Before** (bounced as a wall of text):
```markdown
## Recommendation
We should add a new column because deriving at read time would be slow due to
partition scans, and the OpenSearch path is eventually consistent — see the
long table and the ledger at the end for the trade-offs.
```

**After** (readable-doc):
```markdown
## 🎯 TLDR
- 🟢 **Add** a new counter column, updated only when a message arrives.
- 🔴 **Do not** compute it live on every read (too slow at scale).
- 🟠 On the search copy it can lag a moment (same as today, no worse).

> [!WARNING]
> Do not put a network write on the message-arrival path.

![storage options](/abs/path/options.png)

| Option | Verdict | Why |
|---|:---:|---|
| New column | 🟢 | fast, safe |
| Compute on read | 🔴 | slow at scale |

<details><summary>📋 Full trade-off ledger</summary> ... </details>
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| TLDR at the end / full of jargon | Move to top; plain language; expand acronyms. |
| `<u>` / coloured text / `<span style>` | Stripped. Use `textstyle.py` (U+0332 / small-caps) + bold + emoji. |
| Underlining an identifier (`unread_message_count`) | Underscores fuse into a blur. Use `` `backticks` `` for identifiers. |
| Image with a `"title"` attribute / `<img>` / self-link / image in `<details>` | Title BREAKS it; the rest break or lose zoom. Plain `![alt](path)`, no title. |
| Geometric bullets on bare lines | Collapse to one line. Use normal `-` bullets. |
| Bare jargon (`[V]`, `[R]`, acronyms) left unexplained | Add a one-line legend, or use ꜱᴍᴀʟʟ-ᴄᴀᴘꜱ plain labels (ᴠᴇʀɪꜰɪᴇᴅ / ɴᴇᴇᴅꜱ ᴅᴀᴛᴀ). |
| Small-caps used nowhere | Use it for tags/labels/verdicts (ʀᴇᴄᴏᴍᴍᴇɴᴅᴇᴅ / ʀᴇᴊᴇᴄᴛᴇᴅ / ᴡʜᴀᴛ / ʜᴏᴡ / ʀɪꜱᴋ). It is the distinctive tag look. |
| One big table left inline | Trim to ≤4 cols with an emoji status column, or collapse it. |
| No considered-but-rejected section | Add it. Reviewers check their idea was not missed. |
| Only one diagram | Add the colour-coded current-vs-options decision diagram too. |
| Guessing a new formatting trick works | Probe it first (`verify-first`). |

## Red Flags (STOP)

- "I'll use `<u>` / a coloured span for emphasis" → renders as literal text.
- "A `"title"` on the image is harmless" → it BREAKS the image in plannotator. Drop it.
- "I'll tuck the diagram in `<details>`" → it loses zoom.
- "`[V]`/`[R]` is obvious" → it is not to the reader. Add a legend or use ꜱᴍᴀʟʟ-ᴄᴀᴘꜱ words.
- "The TLDR reads better as a conclusion" → the reader skims top-down; put it first, in plain words.
- "One big table is fine" → walls of text are what gets bounced.
