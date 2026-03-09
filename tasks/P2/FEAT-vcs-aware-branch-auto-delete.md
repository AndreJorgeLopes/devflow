---
id: FEAT-vcs-aware-branch-auto-delete
title: "VCS-Aware Auto-Delete Branch on Merge in devflow init"
priority: P2
category: features
status: open
depends_on: []
estimated_effort: S
files_to_touch:
  - lib/init.sh
  - lib/utils.sh
---

# VCS-Aware Auto-Delete Branch on Merge

## Context

PR #3 added `devflow done` for local cleanup and enabled GitHub's `delete_branch_on_merge` setting via a manual `gh api` call. This should be automated in `devflow init` and support all VCS providers, not just GitHub.

Currently the remote branch auto-delete was configured manually:
```bash
gh api repos/OWNER/REPO -X PATCH -f delete_branch_on_merge=true
```

This only works for GitHub and is not part of `devflow init`.

## Desired Outcome

`devflow init` detects the VCS provider (using existing `detect_vcs_provider()` from `lib/utils.sh`) and enables auto-delete of merged branches on the remote:

| Provider   | API/CLI                                                                 |
|------------|-------------------------------------------------------------------------|
| **GitHub** | `gh api repos/:owner/:repo -X PATCH -f delete_branch_on_merge=true`    |
| **GitLab** | `glab api projects/:id -X PUT --field remove_source_branch_after_merge=true` |
| **Bitbucket** | Not natively supported — document workaround or skip                |
| **Azure DevOps** | Branch policies via `az repos policy` — may require admin         |

## Implementation Notes

- Add as a new init step (e.g., 5e) after hook registration
- Use `detect_vcs_provider()` to determine which CLI/API to call
- Check if the setting is already enabled before modifying (idempotent)
- Require the relevant CLI (`gh`, `glab`, `az`) — skip with warning if not installed
- Should be non-interactive (no prompt needed, safe default)

## Acceptance Criteria

- [ ] `devflow init` enables auto-delete for GitHub repos (via `gh`)
- [ ] `devflow init` enables auto-delete for GitLab repos (via `glab`)
- [ ] Gracefully skips unsupported providers (Bitbucket, Azure) with info message
- [ ] Idempotent — re-running init doesn't error if already enabled
- [ ] Skips with warning if required CLI tool is not installed
