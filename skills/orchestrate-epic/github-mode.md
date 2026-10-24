# GitHub-issues mode (orchestrate-epic bundle file)

Read this file when `gate.py mode <epic>` returned `{"mode":"github",...}`. The epic is a GitHub issue and its child issues are the tickets. Read everything with `gh`. This file replaces only the Jira-specific parts of Phases A, B, C and F. Everything else in SKILL.md applies as written.

## Phase A: find the child issues

Try the sources in this order. Use the first one that gives children:

1. Native sub-issues: `gh api --paginate repos/<owner/repo>/issues/<n>/sub_issues -q '.[].number'`.
2. Task-list items in the epic body: lines that match `^\s*- \[[ xX]\] .*#(\d+)`. (Real case: the signal-copier epic #12 has zero sub-issues. All children are in its "Status per issue" task list.)
3. Neither gives children → ask André for the list. Do not guess from labels or titles.

**A checkbox is not a status.** The epic's task list is often stale (real case: seven items said "PR open" when all seven issues were closed and their PRs merged). Read the state of each child with `gh issue view <n> --repo <owner/repo> --json number,title,state,stateReason,assignees,labels,body,closedByPullRequestsReferences`. List every stale box in Phase D and ask André once before you rewrite the epic body.

Open issues that are not in the epic (a flaky-test issue, an orphan PR) are not tickets. List them for André at the end of Phase D. Do not schedule them.

## Phase B: dependencies

Collect hard blockers from BOTH sources, the same rule as the Jira mode:

1. Native dependencies: `gh api repos/<owner/repo>/issues/<n>/dependencies/blocked_by -q '.[].number'`.
2. Free text in the body: "Depends on #N", "Blocked by #N", "After #N", "Requires #N". Text such as "Found while fixing #N" or "follow-up of #N" is SOFT, not a blocker.

Native dependencies are often empty (real case: `blocked_by` returned `[]` for every signal-copier issue). An empty API result does not mean "no edges". Read the text.

Use `#<n>` as the ticket key in the scheduler. A blocker in another repo is `owner/repo#<n>`, and the scheduler reports it as external.

Branch names must not contain `#`. Use the project key from the issue title when it has one (`[SIM-22] ...` → `feat/SIM-22/<slug>`), else `feat/issue-<n>/<slug>`.

## Phase C: map GitHub state to the scheduler input

Use these fixed rules. Do not choose another mapping:

| GitHub state | `status` | `statusCategory` |
|---|---|---|
| closed, `stateReason` COMPLETED | `Done` | `done` |
| closed, `stateReason` NOT_PLANNED or DUPLICATE | `Closed (not planned)` | `indeterminate` (a dependent stays blocked until André says it is not needed: then add it to `done_signals`) |
| open, with an open PR that closes it | `In Progress` | `indeterminate` |
| open, no PR | `To Do` | `new` |

- An open PR does NOT resolve a blocker. Only a merged PR plus a closed COMPLETED issue does. (A baseline run mapped "open PR" to "In Review", which the scheduler counts as resolved, and that would start dependents on unmerged code.)
- `assignee`: the first assignee's login, or `null`.
- `me`: `gh api user -q .login`.
- Find the PR for an issue: `gh issue view <n> --repo <owner/repo> --json closedByPullRequestsReferences -q '.closedByPullRequestsReferences[].number'`, then `gh pr view <pr> --json state,mergedAt,headRefName` for its state (the reference list does not fill in `state`). No linked PR → use `gh pr list --repo <owner/repo> --head <branch>` with the branch of the route you started.

## Phase F: re-verify "done"

A ticket is done when the issue is closed with `stateReason` COMPLETED AND its PR is merged (`gh pr view <pr> --json state,mergedAt`). The checkbox in the epic body is not evidence. After a ticket is done, tick its box and update its line in the epic body, so the epic stays the single source of truth and the resume guide.

## Labels

A `needs-andre` label (or another label that the project CLAUDE.md names for this) means the ticket needs André. It always goes to a spawned sub-session (SKILL.md routing rule), even if it has a spec and locked tests.
