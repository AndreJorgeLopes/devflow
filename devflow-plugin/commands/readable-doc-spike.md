---
description: [0.27.1] Use when formatting a full engineering spike, PRD, or design-of-record doc for review, when the reader wants the complete team-standard shape (metadata header, TLDR, background, spike goals, architecture diagrams, per-goal investigation, options with a recommendation, considered-but-rejected, database and GraphQL and query changes, migration, cross-project dependencies, testing, effort, phasing, feature-flag strategy, risks, open questions, and a verification appendix). Clean team style, no emoji or tag overload. For a short summary of a spike use readable-doc; for the content use write-spike.
---

# Readable Doc (spike / big)

**You are a staff engineer laying out a full spike the way this team expects to read it.** The reader wants the complete decision-of-record: the recommendation up front, the investigation that backs it, the technical deltas, and every open item and dependency. You make it scannable without dropping rigour.

**Core principle:** completeness with a readable spine. Decision first, evidence reachable but collapsed, every claim grounded.

> [!IMPORTANT]
> This is the formatting layer for a FULL spike. `write-spike` produces the content; this skill shapes it into the team-standard structure. For a short reviewer digest, use `readable-doc`.

## When to Use

- A bigger initiative spike / PRD / design-of-record that needs the full team shape.
- `/devflow:readable-doc-spike <path>` on a full spike doc.
- NOT for a quick summary (use `readable-doc`) or a short plan.

## Running as a command: `/devflow:readable-doc-spike [path]`

`$ARGUMENTS` is the target path.

1. **Resolve the target** (path arg, else the full spike most recently produced/discussed). State the path before writing.
2. **Read the whole doc**, map its content onto the Section skeleton below.
3. **Render the two diagrams** via `render-diagram` (base how-it-works + colour-coded current-vs-options), grouped in Architecture Overview. Reuse current PNGs if present.
4. **Rewrite IN PLACE** in the skeleton + team style. Preserve facts and the author's voice; change structure and formatting.
5. **Self-check:** no `<u>` / no em-dashes / no image `"title"` attr / no GFM alert inside `<details>`; frontmatter (if any) still parses; ticket numbers are not scattered through the prose (they live in the metadata header + References).
6. **Hand back the link:** `PLANNOTATOR_REMOTE=1 PLANNOTATOR_PORT=<port> plannotator annotate <path>` in the background, print the `http://localhost:<port>` URL. Apply annotations and repeat.

## Section skeleton (team-standard order)

1. **Metadata header** (top callout): ticket, epic, blocks-chain, author, date, status, sources. This is where provenance and links live, keeping the prose clean.
2. **TLDR** — decision-first, plain language: what/how/why-this-shape/biggest risk/what needs the team.
3. **Summary** — a short paragraph expanding the TLDR.
4. **Background & Context** — surfaces the counter/feature touches, plus mandatory design constraints from the discussion.
5. **Spike Goals** — enumerated. Tag each Investigation subsection back to its goal ("(Goal 3)").
6. **Architecture Overview** — the two diagrams + a few lines of prose. All diagrams live here.
7. **Investigation Results** — one subsection per goal, the heavy detail. Each ends with a bold **Recommendation** / **Verdict** line. Push the deepest evidence into `<details>` so mid-document does not become a wall.
8. **Options + recommendation** — an options table (Option / description / pros / cons / effort) with an explicit **Recommendation**, and a **considered-but-rejected** / alternative-assessed section stating why each was dropped.
9. **Technical changes** — **Database / schema changes**, **GraphQL changes**, **query changes** (tables of fields/columns), each when applicable.
10. **Migration** — approach favouring **additive / non-blocking / zero-downtime**, with rollback.
11. **Cross-project dependencies** + **Questions for other teams** (sign-offs needed).
12. **Testing strategy** — per layer.
13. **Effort estimates** — S/M/L per area.
14. **Phasing + feature-flag strategy** — phasing ONLY when the work genuinely needs multiple phases (most spikes do not); the flag strategy whenever it ships behind a flag.
15. **Risks** — table (likelihood / impact / mitigation); emphasise the still-open ones.
16. **Open Questions** — the genuinely unresolved items.
17. **Appendix**: **Investigation Log** (the verification ledger: claims grounded in code / origin-main / production, with sample sizes and "directional, not exact" caveats) + **References**.

Drop a section only if the spike genuinely has nothing for it.

## Style (clean team style)

- **Bold** the operative phrase; `code` for identifiers/paths; status circles 🟢🟠🔴❓ as light scan aids in bullets and table cells. Small-caps (`textstyle.py --smallcaps`) sparingly for a verdict word (ʀᴇᴄᴏᴍᴍᴇɴᴅᴇᴅ / ʀᴇᴊᴇᴄᴛᴇᴅ); underline for at most one key phrase.
- **No emoji density, no wall of tags, no table-for-everything.** Tables carry comparisons; prose carries reasoning.
- **Narrative-first, cut buried citations** (team feedback 2026-07-16): ticket numbers / linking data go in the metadata header + References, not scattered through the prose.
- **Collapse deep evidence** into `<details>` so the default read is decision → diagrams → recommendation.
- No em-dashes.

## Plannotator-safe formatting (verified 2026-07-14)

Same matrix as `readable-doc`. Key gotchas: images are plain `![alt](path)` with **no title attribute** (a title breaks them; `<img>`/self-link/in-`<details>` lose zoom or break); GFM alerts render top-level only (**break inside `<details>`** → use `> 🔴 risk: ...` there); tables render fine anywhere; `<u>`/`<span style>`/text-colour are stripped, so underline/small-caps only via `textstyle.py`. Treat any new trick as a claim to probe first (`verify-first`).

## Common Mistakes

| Mistake | Fix |
|---|---|
| No recommendation up front | Decision-of-record in the TLDR + a Recommendation on the options. |
| Investigation Results as one long wall | Per-goal subsections, each ending in a Verdict; collapse deep evidence. |
| Diagrams scattered or in `<details>` | Group both in Architecture Overview, top-level (they lose zoom in `<details>`). |
| Claims not grounded | Investigation Log appendix: verified against code/prod, with sample sizes + caveats. |
| Phasing added by default | Only when genuinely multi-phase. |
| Ticket numbers through the prose | Metadata header + References only. |
| Emoji / tag / table overload | Clean team style; bold + light status circles. |
| Confusing this with the summary | This is the FULL doc; `readable-doc` is the short digest. |
