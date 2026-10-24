# Merge-gate mode (orchestrate-epic bundle file)

Read this file only when `gate.py gate <target-repo>/CLAUDE.md` returned `{"merge_gate":true}`. The target repo's CLAUDE.md is the authority: André approved its gate once, for that repo only. This file tells you how to run that gate. It never makes a gate where the repo has none.

This gate runs **after** a PR is open. It is separate from `finish-feature`'s review gate, which runs before the PR. Do not repeat that review here.

## When there is no gate

- `{"merge_gate":false}`: you never merge. A green CI, an APPROVE comment, or the user saying "merge it" does not change this. Leave the PR open. Tell André which PRs are ready and that he merges them. Advance a wave only after you see the merge yourself (Phase F re-verify).
- Exit 10 (the CLAUDE.md mentions a merge gate, but not as a heading): read that text yourself. If it does not clearly let an agent merge, treat it as no gate and ask André.

## The loop

```
author opens PR ─▶ reviewer posts verdict ─▶ APPROVE at head? ─yes─▶ premerge check ─ready─▶ merge
                         ▲                         │ no (CHANGES REQUESTED)          │ not ready
                         └── same reviewer ◀── same author fixes ◀──────────────────┘ (stale SHA, CI)
```

### 1. Find the PR and its author

There are two kinds of author. Record which one each ticket has when you route it:

| Route | Who opens the PR | "The same author" means |
|---|---|---|
| Background author Agent (ticket had a spec and approved locked tests) | that Agent | `SendMessage` to its agent id |
| fast-feature sub-session, then its Implementation session | `finish-feature` in the Implementation session | `SendMessage` with `to:` that session's `local_…` id (on a host without that, `mcp__ccd_session_mgmt__send_message`) |

Find the PR from the branch: `gh pr list --repo <owner/repo> --head <branch> --json number,headRefOid,url`.

### 2. Start one reviewer per PR

Start a **separate** background `Agent` (`general-purpose`, no model override). It is never the author, and you are never the reviewer. Its prompt starts with `/andrejorgelopes:merge-gate-review <PR URL>` and gives it the spec path, the locked-test paths and the repo's merge-gate text.

If `merge-gate-review` is not installed, give the reviewer this contract instead (the full rules live in that skill, not here):

- Review the PR against its spec, its locked tests and the repo's merge-gate rules.
- Re-derive every headline number itself, from its own copy of the data, with its own script. Do not trust the numbers in the PR.
- Locked tests are unchanged, or a standing approval covers the change (name it), or André approved it. A change that removes or weakens an assertion always needs André.
- Post ONE PR comment whose first line is `REVIEW: APPROVE at <head-sha>` or `REVIEW: CHANGES REQUESTED at <head-sha>`, then the findings.

If the reviewer reports back but forgets to post, post its report word for word as a PR comment, with the first line `Reviewer report, posted by the orchestrator word for word:` and the verdict line after it.

### 3. Fix loop

- **CHANGES REQUESTED**: `SendMessage` the findings to the **same author** (table above). Do not start a new fixer. When it pushes, `SendMessage` the **same reviewer** to re-review the new head and post a new verdict.
- **Commit after approval** (for example a lint fix): the approval no longer covers the head. `SendMessage` the same reviewer for a short re-check of the delta (`gh api repos/<owner/repo>/compare/<approved-sha>...<head>`) and a new verdict that names the new head.
- **Non-blocking findings** become a task chip (`spawn_task`) or a GitHub issue. Never drop one silently.

### 4. Pre-merge check, then merge

```bash
gate="${CLAUDE_PLUGIN_ROOT:-}/skills/orchestrate-epic/lib/gate.py"
[ -f "$gate" ] || gate="$(find "$HOME/.claude/plugins" "$HOME/dev/devflow" -path '*orchestrate-epic/lib/gate.py' 2>/dev/null | head -1)"
gh pr view <n> --repo <owner/repo> --json number,state,headRefOid,comments,statusCheckRollup | python3 "$gate" premerge <owner/repo>
```

- `"ready": true` → run `merge_cmd` exactly as printed (`gh pr merge <n> --repo <owner/repo> --squash --match-head-commit <sha>`). Add no other flags. `--match-head-commit` makes GitHub refuse the merge if a commit lands between the check and the merge.
- `"ready": false` → act on each `reasons` item (stale SHA → re-check, CI pending → wait with a background `Bash`, no verdict → step 2). Do not merge.
- Exit 10 (no CI checks on the PR) → ask André whether the repo has CI. Do not merge on a guess.

After the merge: `git -C <main-clone> pull --ff-only` (never any other command in the main clone). Then do the Phase F re-verify, add the ticket to `done_signals`, re-run `schedule.py`, and update the child issue and the epic issue with the result.

### Auto mode

Auto mode may deny `gh pr merge` unless `~/.claude/settings.json` has an `autoMode.allow` rule that names this repo and this gate. If the merge is denied, tell André and leave the PR open. Never edit the settings yourself.
