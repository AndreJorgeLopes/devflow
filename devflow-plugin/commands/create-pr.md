---
description: [0.11.1] Full PR/MR creation pipeline. VCS-aware (GitHub `gh` / GitLab `glab`), runs self-review + checks, and writes a structured description (TL;DR, change table, mermaid flow, honest verification status, no em-dashes). On GitLab it adapts the project's `.gitlab/merge_request_templates` template, filling its sections and appending only the extras it lacks. Opens as a draft when verification is incomplete.
---

You are creating a pull request (GitHub) or merge request (GitLab). This runs the full pipeline: review, build a structured description, adapt the project template if there is one, and open it with the right tool.

## Steps

1. **Gather context + detect the VCS provider.**

   ```bash
   git log --oneline main..HEAD
   git diff --stat main..HEAD
   git diff main..HEAD
   git remote get-url origin
   ```

   Provider from the remote URL: `*github.com*` -> **github**; `*gitlab.com*` or `*gitlab.*` -> **gitlab**; otherwise **unknown**. (`lib/utils.sh` has the canonical `detect_vcs_provider` / `get_vcs_pr_term` if you can source it; the inline rule above is the fallback.) Also scan the branch name + commits for a ticket ID (e.g. `MES-1234`).

2. **Self-review the diff.** Read the full diff and check for: leftover debug/TODOs, missing error handling, naming-convention violations, files that shouldn't be committed, placeholder/incomplete code, missing tests.

3. **Run checks.**

   ```bash
   devflow check    # or, if unavailable: yarn lint && yarn build && yarn test --changedSince=main
   ```

4. **If self-review or checks surface issues**, report them and ask the user whether to fix first or proceed. Never open a PR/MR with failing checks unless the user explicitly approves.

5. **Build the description content** (provider-independent building blocks). Apply the *Description rules* below:
   - **Title**, concise, conventional (`fix(messaging): stop duplicate carrier retries`).
   - **TL;DR**, one numbered line per change, each with a leading emoji, scannable in 10 seconds.
   - **Changes**, a table mapping file/area -> what changed + *why* (purpose, not mechanics).
   - **Flow**, a Mermaid diagram when the change has a flow/sequence worth showing (skip for trivial one-liners).
   - **Verification**, the honest status: what you actually verified vs what still needs a human.
   - **Ticket**, link if an ID was found.

6. **Assemble the body for the provider** (see *Provider assembly*). GitHub -> the devflow structured body. GitLab -> adapt the project's MR template if one exists, else the structured body.

7. **Present the draft** (title + final body + whether it'll open as draft or ready) and get approval.

8. **Create it** (see *Creating the PR/MR*). Push first, write the body to a file (not a heredoc), open with the provider's CLI, draft when verification is incomplete.

9. **Return the URL.**

## Description rules (all providers)

- **No em-dashes anywhere** in the title or body. Use commas, periods, parentheses, or `->`. (Em-dashes read as machine-written and are a hard no.)
- **Lead with the TL;DR.** One numbered line per change, leading emoji, purpose-first.
- **Frame by purpose, never mechanics.** "Fixed X so Y stops happening", not "19 commits to branch Z" or "changed 4 files". Commit counts only ever appear parenthetically, never as a headline.
- **Changes table**: `file / area | what + why`.
- **Mermaid** only when it earns its place (a real flow, sequence, or before/after). Don't diagram a one-line change.
- **Honest verification.** Use ✅ only for what you actually confirmed, and say how ("verified by a live run", "tests pass"). Use ⚠️ for anything still needing a rebuild, a human click-through, or a manual step. Never mark ✅ what you did not check.
- **Draft when unverified.** If any verification item is ⚠️, or checks didn't fully pass, open as a **draft** and say why. Ready only when it's genuinely ready.

## Provider assembly

### GitHub, structured body

````markdown
## TL;DR
1. 🟢 <one line per change, purpose-first>

## Changes
| File / area | What + why |
|---|---|
| ... | ... |

## Flow
```mermaid
<diagram, if useful>
```

## Verification
- ✅ <verified thing> (<evidence>)
- ⚠️ <still needs> (<what + who>)

## Ticket
<link or N/A>

## Checklist
- [ ] Tests pass
- [ ] Lint passes
- [ ] Types check
- [ ] Self-reviewed
- [ ] CLAUDE.md compliance verified
````

### GitLab, adapt the project's MR template

1. **Discover the template:**

   ```bash
   ls .gitlab/merge_request_templates/*.md 2>/dev/null
   ```

   Pick, in order: a file named `Default.md` (case-insensitive); else the project's configured default if known; else the single template if there's only one; else the one whose name best matches the change (e.g. `Bug.md` for a fix), and note the choice. If none exist, use the GitHub structured body above (it renders fine on GitLab).

2. **Treat the chosen template as the skeleton.** Its headings, checklists, GitLab quick-actions (`/label`, `/assign`, `/milestone`), Jira/links lines, and HTML `<!-- ... -->` markers are **load-bearing, preserve them verbatim.**

3. **Fill its sections** by mapping headings (case-insensitive, fuzzy):
   - *Description / Summary / What / Context / Why* <- the TL;DR + Summary bullets
   - *Changes / What changed / Implementation* <- the Changes table
   - *Testing / QA / How to test / Validation* <- the Verification status
   - *Ticket / Issue / Jira / Related* <- the ticket link

   Leave any template section you have nothing for **unchanged** (never delete a section).

4. **Append a compact block ONLY for extras the template has no slot for:**

   ```markdown
   ## Process (devflow)
   <TL;DR if it wasn't placed above> · <mermaid flow if useful> · <verification status if there was no Testing slot>
   ```

5. **Fallback:** if you cannot confidently match *any* heading (free-form template), keep the template verbatim and append the full GitHub-style structured block after it. Never mangle a template you don't understand.

6. **When UPDATING an existing description later** (not first creation), splice around existing bot markers (e.g. Cursor `<!-- CURSOR_SUMMARY -->...<!-- /CURSOR_SUMMARY -->`), preserve them verbatim, never full-replace the body. See CLAUDE.md "MR/PR descriptions, splice, don't replace".

## Creating the PR/MR

Write the final body to a file with the **Write tool** (a heredoc-to-file can silently land 0 bytes, see CLAUDE.md). Then:

```bash
git push -u origin HEAD
```

- **GitHub:**
  ```bash
  gh pr create --title "<title>" --body-file /tmp/devflow-pr-body.md   # add --draft when verification is incomplete
  ```
- **GitLab:**
  ```bash
  glab mr create --title "<title>" --description "$(cat /tmp/devflow-mr-body.md)" --target-branch <default-branch> --yes   # add --draft when incomplete
  ```
  Pass `--target-branch` explicitly (default branch) so the MR doesn't target the wrong base. The company remote may require a Jira pattern like `MES-1234` in the commit message, not just the branch, see CLAUDE.md.
- **unknown provider:** print the compare URL and the full body so the user can open it manually.

Draft logic: open as **draft** when any verification item is ⚠️ or checks didn't all pass; otherwise ready. State which and why.

## Important

- Never open a PR/MR with failing checks unless the user explicitly approves.
- Always push the branch before creating.
- Diff > 500 lines -> suggest splitting into smaller PRs/MRs.
- The conversational reviewer-voice rule is for *review comments*, not this description, the description stays structured.

$ARGUMENTS
