---
description: [0.23.0] Use when you have a full spike, PRD, or long design doc and want a tight, scannable SUMMARY of it for a busy reviewer. Condenses the source into a super-short TLDR, one all-in-one diagram, the recommendation, spike goals, still-open options, open questions, open risks, the technical deltas (GraphQL / DB / query), additive migration, external dependencies, and feature-flag strategy, with a link back to the full doc. Clean team style, no emoji or tag overload. For the full spike itself use readable-doc-spike; for the content use write-spike.
---

# Readable Doc (small summary)

**You are an engineer summarising a long spike for a reviewer who has two minutes.** The full doc already holds every detail; your job is to surface only the decision, the must-know technical deltas, and the genuinely open items, and to link back for depth. A good summary lets a reviewer approve or push back without opening the full doc.

**Core principle:** a summary is a filter, not a rewrite. Keep the source doc intact; produce a separate short summary that points into it.

> [!IMPORTANT]
> This skill is the summary/formatting layer, not the content. `write-spike` produces the full spike; `readable-doc-spike` formats the full spike; this skill distils either into a small summary.

## When to Use

- A `write-spike` run (or any long spike / PRD / design doc) is done and you want a reviewer-facing digest.
- A reviewer asked for "the short version" / "just the decision and the open questions".
- `/devflow:readable-doc <path>` on a long doc.

## Running as a command: `/devflow:readable-doc [path]`

`$ARGUMENTS` is the source doc path.

1. **Resolve the source.** If `$ARGUMENTS` names a file, use it. If empty, use the full spike/PRD most recently produced or discussed this session. State the resolved path in one line before writing.
2. **Read the whole source** and pull out only: the decision, spike goals, still-open options, open questions, open risks, technical deltas, migration, external deps, feature-flag strategy.
3. **Write a SEPARATE summary** at `<source-stem>-summary.md` next to the source (do not overwrite the full doc). Use the Summary contents below.
4. **Reuse one diagram.** If the source has a suitable diagram, embed that one (plain `![alt](/abs/path)`, no title attribute). Otherwise render one all-in-one diagram via `render-diagram`. One diagram only.
5. **Self-check:** no `<u>`, no em-dashes, no image `"title"` attr, no GFM alert inside `<details>`; ticket numbers and linking data are NOT scattered through the prose (they live in the link-back / references only).
6. **Hand back the link.** `PLANNOTATOR_REMOTE=1 PLANNOTATOR_PORT=<port> plannotator annotate <summary-path>` in the background, print the `http://localhost:<port>` URL. Apply returned annotations and repeat.

## Summary contents (in this order; drop a section if the source genuinely has nothing for it)

1. **TLDR** — 3 to 5 lines, plain language: what was decided, why, and the single biggest open thing. A non-specialist should get the decision.
2. **One diagram** — the all-in-one how-it-works / options picture.
3. **Recommendation** — one line: the chosen approach (the decision of record).
4. **Spike goals** — the questions the spike set out to answer, one line each.
5. **Still-open options** — only viable options NOT yet confirmed (with the one-line trade-off). Omit settled/rejected ones.
6. **Open questions** — only the genuinely unresolved ones.
7. **Open risks** — only risks that cannot be answered right now.
8. **Technical deltas** — call out any **GraphQL change**, **DB/schema change**, or **query change** explicitly (a short table is fine here). This is the part implementers scan for.
9. **Migration** — the approach, favouring **additive / non-blocking** migrations that do not break or block anything.
10. **External dependencies** — only cross-project dependencies on teams outside ours.
11. **Feature-flag strategy** — if the change ships behind a flag, how.
12. **Decided / locked** (optional) — 1 to 2 lines of settled inputs, so reviewers do not reopen them.
13. **Full doc** — a link back to the source spike/PRD for the evidence and detail.

Put any section that runs long into a `<details>` block so the default view stays short. Sizing / phasing does NOT belong in the small summary (that is `readable-doc-spike`, and only when genuinely multi-phase).

## Style (clean team style, not heavy)

- Plain markdown. **Bold** the operative phrase; `code` for identifiers/paths. Light use of status circles 🟢 done/safe · 🟠 caution · 🔴 open risk · ❓ open question as a bullet or table prefix.
- **No emoji density, no wall of small-caps tags, no table-for-everything.** Small-caps (via `textstyle.py --smallcaps`) at most for a one-word verdict; underline (`textstyle.py`) for at most one key phrase. Reach for prose + bold first.
- **Narrative-first and concise** (team feedback, 2026-07-16): prioritise a readable story. **Cut granular citations** — do not scatter ticket numbers / linking data through the prose; they hurt readability. Provenance goes in the Full-doc link / a References line, not inline.
- No em-dashes: use commas, periods, parentheses, "since"/"so".

## Plannotator-safe formatting (correctness, verified 2026-07-14)

The renderer allows a small tag set and strips the rest. Both this skill and `readable-doc-spike` follow it.

| Want | Use | Never |
|---|---|---|
| Callout | GFM alert `> [!NOTE]/[!WARNING]/[!TIP]` (top-level only) | a GFM alert inside `<details>` (breaks) → use `> 🔴 risk: ...` emoji blockquote there |
| Image / diagram | plain `![alt](path)`, no title attr (renders + zooms) | `"title"` attr (breaks it), `<img>` (no zoom), self-link `[![]()]()`, image in `<details>` (loses zoom) |
| Collapse | `<details><summary>...</summary> ... </details>` (tables/bullets fine inside) | a GFM alert or a diagram inside it |
| Colour | status emoji in text / a table column | text colour via `style` (not applied) |
| Underline / small-caps | Unicode via `textstyle.py` (U+0332 / small-caps), sparingly | `<u>` `<ins>` `<mark>` `<span style>` (all stripped) |
| Table | compact markdown, emoji status column | wide walls of text |

## Common Mistakes

| Mistake | Fix |
|---|---|
| Overwriting the full spike | Write a separate `-summary.md`; keep the source. |
| Copying the whole doc | It is a summary. Cut evidence, measurements, background prose. |
| Ticket numbers scattered in prose | Move to the Full-doc link / References (team readability rule). |
| Emoji / small-caps-tag / table overload | Clean team style; bold + light status circles. |
| More than one diagram | One all-in-one diagram in the summary. |
| Listing rejected options | Small summary carries only still-open viable options + the recommendation. |
| Sizing/phasing in the summary | That is big-only (`readable-doc-spike`), multi-phase only. |
