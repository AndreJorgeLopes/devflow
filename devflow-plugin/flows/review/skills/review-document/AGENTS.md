# Review agents — definitions and activation rules

Loaded by `SKILL.md` Phase 2 in Thorough mode. Each agent receives the context packet (cleaned doc text + `DOC_TYPE` + `ANCHOR_TYPE` + linked tickets + external sources + Hindsight memories + `EXISTING_COMMENTS` + relevant code excerpts for technical doc types).

In Thorough mode, dispatch all active agents **in a single message with multiple `Agent` tool uses** so they run in parallel. Each agent returns findings as structured JSON (see "Finding format" below).

## Subagent selection — prefer OMC specialists when available

If `oh-my-claudecode` is installed (detect via `omc --version` succeeding OR the presence of `/oh-my-claudecode:*` slash commands), use the specialized OMC agent for each role. Generic-purpose fallback otherwise.

| Role | OMC specialist | Generic fallback |
|---|---|---|
| Correctness + structure + completeness | `critic` (Opus) | `general-purpose` |
| Prose / tone / clarity / audience-fit | `writer` (Haiku) | `general-purpose` |
| External claim verification (vendor / API / regulatory docs) | `document-specialist` | `general-purpose` |
| Code / runtime claim verification | `verifier` | `general-purpose` |
| Architecture / system-layering claim cross-check | `architect` (Opus, read-only) | `general-purpose` |
| Security / PII / auth claim audit | `security-reviewer` | `general-purpose` |
| Visual / UI screenshot validation | `visual-verdict` skill (invoked SEQUENTIALLY after the parallel agent batch returns — it is a skill, not a subagent dispatchable via `Task`) | n/a |

Fallback is a real fallback — never block the review on OMC absence. Findings from `general-purpose` are still high quality, just less role-specialized.

## Always-on agents per `DOC_TYPE`

| `DOC_TYPE` | Always-on (3 agents) |
|---|---|
| `kb` (customer-facing knowledge base) | `critic` + `writer` + `document-specialist` |
| `spike` / `rfc` | `critic` + `verifier` + `architect` |
| `prd` | `critic` + `writer` + `verifier` |
| `runbook` | `critic` + `verifier` + `security-reviewer` |
| `design` (UI prose) | `critic` + `writer` (always-on subagents); also run `visual-verdict` skill sequentially after the batch returns if screenshots are present |
| `generic` | `critic` + `writer` + `document-specialist` |

## Conditional agents (activate when signal triggers)

| Agent | Activate when |
|---|---|
| `security-reviewer` | Doc mentions auth / tokens / PII / SSO / encryption / GDPR / customer data export / DSAR |
| `architect` | Doc claims behaviour of ≥2 services OR includes a system-layering diagram |
| `visual-verdict` skill (sequential, not a parallel subagent) | Doc references screenshots, UI mocks, or embedded images |
| `verifier` | Doc claims runtime behaviour of code that exists in the current workspace |
| `document-specialist` | Doc cites external vendor / API / regulatory sources (URLs in body) |

Conditional agents are dispatched in parallel with the always-on set.

## Agent prompts per role

Each agent receives the context packet plus a role-specific prompt. Adapt these per invocation — they are starting points, not rigid templates.

### Critic — correctness + structure + completeness
Review for: factual contradictions inside the doc, missing sections a reader would reasonably ask, structural flow, ambiguity, audience-fit. Output severity-tagged findings with anchor + verbatim quote + one-sentence why + concrete fix. **Do NOT flag styling.** Watch for: terminology drift (same concept named two ways), self-contradicting sentences, sections that contradict each other, missing edge cases.

### Writer — prose / tone / clarity
Review for: tone consistency across the doc, reading level vs declared audience, jargon density, passive voice that obscures who-does-what, awkward sentences, unclear CTAs. Output 5–10 specific `quote → rewrite` pairs. **Do NOT flag substance** — that is the critic's job. Limit findings to where rewriting the sentence concretely improves comprehension.

### Document-specialist — external claim verification
Verify factual claims about external systems (vendor APIs, regulations, third-party SDKs) against authoritative upstream sources. Use the `defuddle` skill for clean web fetches. Time-box: ≤8 fetches, ≤15 minutes total. **Authoritative sources only** — vendor's own docs (developers.facebook.com, business.whatsapp.com, twilio.com/docs, etc.). Secondary BSP / SDK provider docs (Infobip, Vonage, etc.) acceptable as confirmation, never primary. Reject random blogs / Stack Overflow / tutorials as evidence. Output a verification table: `Claim | Doc quote | Source URL | Verdict (confirmed / partial / not-found / contradicted) | Notes`. End with `"claims to verify in-person with PM"` — flag claims that need internal-team confirmation (e.g. "is this an Aircall product decision or a Meta restriction?").

### Verifier — code / runtime claim cross-check
For each doc claim about how the code behaves: `Grep` the workspace, `Read` the relevant file, confirm or contradict. Output: `Claim | file:line | Verdict | Quote of actual code`.

### Architect — architecture / system-layering claim cross-check
Read the doc's "how it works" / data-flow / sequence-diagram sections. Cross-check against actual service code in the workspace. Surface mismatches between what the doc describes and what the code does. Read-only — do not propose code changes, only flag doc/code drift.

### Security-reviewer — PII / auth / secrets / GDPR
Audit the doc for: secrets in examples (API keys, tokens, real customer phone numbers), customer-data exposure in code samples, missing GDPR / data-residency notes, OWASP-relevant claims (auth flow descriptions that contradict reality), DSAR-handling claims. Output severity-tagged findings.

## Finding format (JSON returned by every agent)

```json
[{
  "agent": "critic",
  "severity": "critical|important|suggestion",
  "confidence": 85,
  "category": "factual|consistency|completeness|clarity|tone|security|verification|missing-section",
  "anchor_type": "file_line|section_quote",
  "file": "/abs/path/to/doc.md",
  "line": 42,
  "section": "What is X?",
  "quote": "verbatim text snippet from the doc",
  "title": "Short description (the bionic-reading key term)",
  "detail": "Full explanation grounded in the cleaned doc text and any verified source",
  "suggestion": "Concrete fix — inline rewrite verbatim, or one-sentence instruction",
  "external_source_url": "https://... (REQUIRED for document-specialist findings; null otherwise)"
}]
```

**`anchor_type` semantics:**
- `file_line` — local file. Populate `file` + `line`, omit `section` (or include for context).
- `section_quote` — hosted doc. Populate `section` + `quote` (verbatim snippet user can Ctrl+F). Omit `file` + `line`.

The skill orchestrator sets the global `ANCHOR_TYPE` in Phase 0c and passes it to each agent. Agents emit findings in the matching shape; the orchestrator validates before output.

## Recurring-pattern handling

If an agent finds the SAME issue class at >3 anchors (e.g. passive voice across 6 paragraphs, vendor-name-capitalization drift across 5 sections), it MUST collapse to one finding with `category: "recurring"` and list the affected anchors in `detail`. Per-instance flagging produces noise.
