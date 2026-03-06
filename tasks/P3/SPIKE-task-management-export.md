---
id: SPIKE-task-management-export
title: "Task Management Export Format"
priority: P3
category: spikes
status: open
depends_on: []
estimated_effort: M
files_to_touch: []
---

# Task Management Export Format

## Context

Our task tickets in `tasks/` use YAML frontmatter-based markdown files. These should be exportable to Linear, Jira, or any vendor's task management system. Research whether a vendor-agnostic intermediary format exists, how to map our fields to external APIs, and how to build a `devflow tasks export` command.

## Research Questions

1. Does a vendor-agnostic task format exist? (e.g., Open Project, TaskPaper, Todo.txt, or an emerging standard)
2. Can our YAML frontmatter-based tickets be automatically converted to:
   - Linear issues via API
   - Jira issues via API
   - GitHub Issues via API
3. Should we use an intermediary format (like a normalized YAML/JSON schema) that maps to all vendors?
4. Can we integrate with the Kanban board (SPIKE-P3-003) for bidirectional sync?
5. How do we handle fields that exist in one system but not another? (e.g., `estimated_effort` may not map cleanly)
6. What about rich content (markdown body) — do all targets support markdown natively?

## Investigation Steps

1. **Research Linear API** (https://developers.linear.app/)
   - Document issue creation endpoint and required/optional fields.
   - Map our frontmatter fields to Linear issue fields.
   - Test API with a sample ticket export.
   - Check rate limits and authentication methods.

2. **Research Jira API** (https://developer.atlassian.com/cloud/jira/platform/rest/v3/)
   - Document issue creation endpoint and required/optional fields.
   - Map our frontmatter fields to Jira issue fields.
   - Test API with a sample ticket export.
   - Note Jira-specific quirks (project keys, issue types, custom fields).

3. **Research GitHub Issues API**
   - Map our fields to GitHub Issues (labels for priority/category, milestones for sprints).
   - Evaluate as a lightweight alternative for open-source projects.

4. **Field mapping exercise**
   - Create a comprehensive mapping table of all our frontmatter fields to each vendor.
   - Identify gaps and propose solutions (custom fields, labels, conventions).

5. **Prototype export command**
   - Build a minimal `devflow tasks export --target linear --dry-run` that generates the API payload without sending it.
   - Validate the payload against the target API's schema.

6. **Research intermediary formats**
   - Evaluate Todo.txt, TaskPaper, and other plain-text task formats.
   - Check if any standardization efforts exist in the DevOps/project management space.

## Expected Deliverables

- **Field mapping table**:

  | Our Field        | Linear Field | Jira Field        | GitHub Issues Field | Notes                          |
  | ---------------- | ------------ | ----------------- | ------------------- | ------------------------------ |
  | id               | identifier   | key               | number              | Auto-generated on target       |
  | title            | title        | summary           | title               | Direct mapping                 |
  | priority         | priority     | priority          | label:priority/\*   | Enum mapping needed            |
  | category         | label        | component         | label               | Mapping varies                 |
  | status           | state        | status            | state               | Enum mapping needed            |
  | depends_on       | relation     | issueLink         | —                   | Not supported in GH            |
  | estimated_effort | estimate     | storyPoints       | label:effort/\*     | Custom field likely            |
  | body (markdown)  | description  | description (ADF) | body                | Jira uses Atlassian Doc Format |

- **Proposed export command spec**:
  - `devflow tasks export --target <linear|jira|github> [--dry-run] [--file <path>]`
  - `devflow tasks import --source <linear|jira|github> [--query <filter>]`
  - `devflow tasks sync --target <linear|jira|github> [--bidirectional]`

- **Recommended intermediary format** (if needed) — a normalized JSON/YAML schema that can be losslessly converted to/from our markdown format and each vendor's API format.

- **Prototype**: Working `--dry-run` export for at least one vendor.

## Decision Criteria

- **Lossless round-trip**: Export → import should preserve all meaningful data. If lossy, document exactly what is lost.
- **Vendor-agnostic core**: The intermediary format (if used) must not favor one vendor over another.
- **Incremental adoption**: Export should work without requiring users to change their existing ticket format.
- **Markdown fidelity**: The body content (markdown sections like Context, Research Questions, etc.) must be preserved in the target system.
- **Idempotent**: Running export twice should not create duplicate issues — support upsert semantics.

## Technical Notes

- Jira's description field uses Atlassian Document Format (ADF), not markdown. A markdown-to-ADF converter will be needed (libraries exist: `md-to-adf`, `jira-wiki-markup`).
- Linear natively supports markdown in descriptions — simplest target for initial implementation.
- GitHub Issues also supports markdown natively — good second target.
- Consider storing the external ID (e.g., `linear_id: LIN-123`) in our frontmatter after first export to enable subsequent syncs.
- The `depends_on` field maps to issue links/relations in Jira and Linear but has no native equivalent in GitHub Issues.
- This spike has a dependency relationship with SPIKE-P3-003 (Kanban Board Integration) — shared task model could serve both.
