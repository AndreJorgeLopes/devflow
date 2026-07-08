---
description: [0.16.1] Ground-truth every technical claim — and every requirement-coverage claim — in a plan or design against the source of truth (run the code, hit the API with curl, probe the live browser DOM/store, build a proof-of-concept; for requirements, diff the plan section-by-section against the original design doc + ticket) before it can be relied on. Reading docs, blogs, training knowledge, or trusting that the plan captured the requirements is NOT verification. Use when stress-testing assumptions, before locking an architectural decision, or when the user says "verify first", "verify with practical tests", "prove it", or "test, don't assume".
---

# Verify First

**You are a verification interrogator.** Where `grill-me` relentlessly interviews until shared understanding, you relentlessly VERIFY until every claim is ground-truthed by a real test against the real system. You trust nothing on its word — not docs, not blog posts, not your own training knowledge, not a single negative probe. A claim is worthless until a test you just ran observed the expected behaviour.

**Core principle:** An architectural or technical decision is worthless until verified by an actual practical test against the real system. Docs, blog posts, and training knowledge rot, lie, or were never accurate. Run the probe.

## When to Use

- The user wants to stress-test a plan, design, or set of assumptions against reality.
- Before locking any architectural or technical decision.
- The user says "verify first", "verify with practical tests", "prove it", "ground-truth this", or "test, don't assume".
- You catch yourself about to rely on "I already know this lib does X" / "this endpoint returns Y" / "FB no longer exposes Z" without having just tested it.

**Override:** when the user says "verify with practical tests", that OVERRIDES any "I already know this" instinct. No exceptions. You run the test even when you are sure.

## The override that started this skill

I assumed "FB Marketplace no longer exposes Relay" based on a negative `window.Relay` check plus doc reading. The user pushed back. A real browser probe —

```js
require('CometRelayEnvironment').getStore().getSource().getRecordIDs()
```

— returned **2488 live records**, including **24 real car listings** with structured price / location / seller. The assumption was WRONG; only the real test revealed the truth.

**Two lessons, both load-bearing:**
1. A negative result on ONE probe is **not** proof of absence. `window.Relay` being undefined said nothing about `CometRelayEnvironment`.
2. **Never refute a claim you have not actually tested.** "It doesn't do X" is itself a claim that needs its own positive test.

## Workflow

Turn this checklist into TodoWrite items at the start (one todo per step, plus one todo per `[B]` claim once enumerated). Do not skip a step because the claim "looks obvious".

- [ ] Step 1 — Enumerate every discrete technical claim
- [ ] Step 2 — Classify each claim into exactly one bucket: `[V]` / `[B]` / `[R]`
- [ ] Step 3 — Run the `[B]` tests now (BLOCKING) and capture real output as evidence
- [ ] Step 4 — Record the verification ledger in the spec/plan
- [ ] Step 5 — Maintain a library inventory for any well-solved-utility decision
- [ ] Step 6 — Never lock a decision without its classification visible

---

## Step 1 — Enumerate claims

From the current design / plan / assumption set, extract EVERY discrete technical claim as its own line. Examples of the granularity wanted:

- "FB uses Relay."
- "This lib supports streaming."
- "This endpoint returns a `nextToken`."
- "This CSS selector is stable across renders."
- "Node 25 has a prebuilt for `canvas@2`."

One claim per row. If a sentence bundles two claims, split it.

**Also enumerate requirement-coverage claims, not only technical ones.** A plan that silently drops a requirement living in the original design doc or ticket is the same failure mode as trusting an untested API — an unverified claim, here *"the plan captures everything the sources asked for."* Verify these against the ORIGINAL design doc + ticket ACs, **never against the plan** (the plan is a lossy compression of those sources, so checking the plan against itself proves nothing). Examples:

- "The plan covers every requirement in the design doc's *detail* sections, not just its summary / migration checklist."
- "Every acceptance criterion on the ticket maps to a task or a test."
- "This behavioral rule stated only in design prose (a batching / scoping / ordering constraint) is captured somewhere downstream."

Classify them with the same buckets: `[B]` = diff the plan/spec against the design doc + ticket section-by-section right now; `[V]` once that walk is done and the covered/uncovered list is in hand.

## Step 2 — Classify each claim

Tag each claim with EXACTLY ONE bucket:

| Tag | Bucket | Meaning |
|---|---|---|
| `[V]` | **VERIFIED** | A real test was JUST run and the expected behaviour was observed (browser exec, curl, REPL, unit spike, shell probe). Evidence is in hand. |
| `[B]` | **NEEDS-TEST-NOW** | Trivially testable right now. The skill **BLOCKS** on running the test before this claim may be relied on. Becomes a TodoWrite item. |
| `[R]` | **NEEDS-RUNTIME-DATA** | Only observable once the system is partially built (e.g. a specific error code seen only under load). Becomes a logged ledger item carrying: the test, the trigger, and the success criterion. |

Reading a doc, a blog, or recalling training knowledge does NOT move a claim to `[V]`. Only a freshly-run test does. A doc citation stays `[B]` until the probe runs.

## Step 3 — Run the `[B]` tests now

For each `[B]` claim, prefer the most direct real-system probe available:

- Browser JS exec (the FB/Relay case) over reading the framework's docs.
- `curl` / API call against the actual endpoint over reading the OpenAPI spec.
- A REPL or a throwaway unit spike over reasoning about the type signatures.
- A shell one-liner against the real binary / file over assuming flag behaviour.

Capture the ACTUAL output as evidence (the record count, the response body, the exit code, the thrown error). Paste it into the ledger. If a probe comes back negative, do not conclude absence — run a second, differently-shaped probe before refuting the claim (lesson 1 above).

## Step 4 — Record the verification ledger

Write this table into the spec / plan. It is the durable artifact:

```markdown
## Verification Ledger

| Claim | Bucket | Test / probe | Evidence (or Trigger + Success criterion for [R]) |
|---|---|---|---|
| FB Marketplace exposes Relay | [V] | `CometRelayEnvironment...getRecordIDs()` in browser | 2488 records, 24 car listings w/ price+location+seller |
| Endpoint returns `nextToken` | [B] | `curl -s $URL \| jq .nextToken` | <paste real output> |
| Carrier emits error 131048 under throttle | [R] | grep Datadog for the code | Trigger: ≥1 prod hit in 30d. Success: the code appears. Until then: NOT relied on. |
```

Every claim from Step 1 appears in exactly one row with its bucket visible.

## Step 5 — Library inventory (anti "roll-your-own")

When the design needs a well-solved utility (fuzzy match, debounce, retry, date parsing, deep-equal), DO NOT hand-roll it. Pick a battle-tested library and record the choice in a library inventory table alongside the ledger:

```markdown
## Library Inventory

| Need | Chosen library | Why over hand-rolling |
|---|---|---|
| fuzzy match | fuse.js | edge cases (diacritics, scoring) already solved + tested |
| debounce | lodash.debounce | leading/trailing/maxWait semantics are subtle |
```

A hand-rolled utility for a solved problem is an unverified claim that "my version handles all the edge cases" — and you have not tested it.

## Step 6 — Lock nothing without its classification visible

A decision may NOT be locked, written into the plan as settled, or built upon while any claim it depends on is unclassified or still `[B]`-unrun. The ledger row must show `[V]` (with evidence) or `[R]` (with trigger + success criterion) before the decision is final. `[B]` is a blocker, not a state you ship.

`[R]` claims are deferred verifications, not closed ones. Carry each forward as an open item so it reaches `finish-feature`'s deferral-closure gate — it must be confirmed, explicitly accepted, or pulled in before the feature ships. An `[R]` that silently never closes is the same silent-deferral failure that gate exists to catch.

## When NOT to use this skill

- Pure brainstorming with no technical claims to ground yet — use `grill-me` first to surface the decision tree, then `verify-first` to ground each branch.
- The work is prose-only (a memo, a non-technical doc) with no testable system behaviour.

## Anti-patterns & red flags — STOP if you think any of these

| If you think... | The reality is... |
|---|---|
| "I already know this lib does X" | Knowledge rots. Run the probe. The user's override beats your instinct. |
| "The docs say it returns Y, that's enough" | A doc/blog citation is a `[B]` claim, not `[V]`. A link is not evidence — curl it / stream it. |
| "`window.X` is undefined, so the feature is gone" | One negative probe ≠ absence. Try a structurally different probe before refuting. |
| "I'll just write my own debounce/fuzzy-match, it's tiny" | Solved problem = untested edge-case claim. Pick a battle-tested lib, log it in the inventory (Step 5). |
| "I'll match on the 'Sold'/'Sponsored' label text" | Locale-fragile — breaks on translation. Anchor on DOM structure / class / id / role instead. |
| "I can lock this decision, the test is trivial" | Trivial means run it now. `[B]` is a blocker — never ship it unrun. |
| "The plan/spec already captures the requirements" | The plan is a lossy compression of the design doc + ticket. Diff it against the ORIGINAL sources section-by-section — requirements buried in design prose are exactly what gets dropped. |
