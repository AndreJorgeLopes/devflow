# Spike Document Template

Reference template for `/write-spike`. Every section must be populated or explicitly marked "TBD — [reason], tracked in [task file]".

## Template

```markdown
# [SPIKE] <Initiative Name>

> **Ticket:** <ID> | **Author:** <name> | **Date:** <YYYY-MM-DD>
> **Deadline:** <date> | **Status:** Draft
> **Signed off by:** <pending>

## Summary

<One paragraph: what we're investigating, why it matters, timeline pressure, scope boundaries>

## Background & Context

<Business context, regulatory/competitive pressure, ROI justification>
<Link to PRD if exists, link to initiative epic>

## Spike Goals

1. <Goal>
2. <Goal>
...

## Architecture Overview

` ``mermaid
graph TB
    %% Affected services with impact coloring
    %% Red = high impact, Orange = medium, Yellow = low
` ``

<Narrative: which services affected and how they relate>

## Investigation Results

### 1. <Layer/Goal Name>

**Current State:**
<What we handle today — code references where applicable>

**Gap:**
<What needs to change>

**Options:**

| Option | Description | Pros | Cons | Effort |
|--------|-------------|------|------|--------|
| A | ... | ... | ... | S/M/L |
| B | ... | ... | ... | S/M/L |

**Recommendation:** Option <X> because <rationale aligned with business timeline>

**Data Flow:**

` ``mermaid
sequenceDiagram
    %% Key interaction for this layer
` ``

<Repeat per spike goal>

## Database Changes

### Schema Changes

| Table | Change | Type | Locking? | Migration Strategy |
|-------|--------|------|----------|-------------------|
| ... | ... | ADD COLUMN (nullable) | No | Additive |

### Migration Approach

**Company precedent:** <Past MR reference, who did it, pattern used>
**Access required:** <Who has DB write access, approval process>
**Zero-downtime strategy:** <Expand-and-contract / CONCURRENTLY / batching>
**Non-locking alternatives:** <PG11+ ADD COLUMN WITH DEFAULT, pg_repack, gh-ost>
**Batching strategy:** <Batch size, ordering (oldest first), monitoring>
**Rollback plan:** <What if migration fails midway>

## Cross-Team Dependencies

| Team | Contact(s) | What We Need | Status | Deadline |
|------|-----------|--------------|--------|----------|
| ... | ... | ... | Pending | ... |

## Questions for Other Teams

### Questions for <Team Name>
- <Question>

### Questions for Product / Design
- When will designers join this initiative?
- <Business priority questions>

## Testing Strategy

| Layer | What to Test | How | Complexity | Cross-Team? |
|-------|-------------|-----|-----------|-------------|
| ... | ... | Unit / Integration / E2E / Manual | S/M/L | Yes/No |

## Effort Estimates

| Area | Effort | Dependencies | Notes |
|------|--------|-------------|-------|
| ... | S/M/L | Blocked by X | ... |

**Total estimated effort:** <range>

## Phasing

### Phase 1: Must ship by <deadline>
- <Required items>

### Phase 2: Can follow
- <Deferrable items>

### Gating
- <Plan tier, customer segment restrictions>

## Risks & Open Questions

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| ... | H/M/L | H/M/L | ... |

**Open questions:**
- <Remaining unknowns>

## Review Checklist

> For the reviewing engineer:
> - [ ] Architectural options make sense for our stack and timeline
> - [ ] Effort estimates feel realistic based on your experience
> - [ ] No critical integration points were missed
> - [ ] Database migration strategy is safe for our scale
> - [ ] Cross-team dependencies are correctly identified
> - [ ] Testing strategy covers the highest-risk areas

## Follow-Up Tickets (Draft)

> NOT yet created in tracker. Review and create after spike approval.

### Ticket 1: <title>
- **Scope:** <description>
- **Acceptance criteria:** <list>
- **Effort:** S/M/L
- **Dependencies:** <list>

## Appendix

### Investigation Log
<Findings from hands-on investigation>

### References
- <Links to external docs, past spikes, related MRs>
```
