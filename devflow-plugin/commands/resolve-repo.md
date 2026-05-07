---
description: Resolve the correct repository for a task — detect VCS platform, match ticket to repo, clone if missing. Run this in a sub-agent to avoid filling main context.
---

You are resolving which repository a task should be worked on. This skill handles VCS platform detection, scoped repo discovery, and cloning when needed.

**IMPORTANT:** This skill is designed to run inside a **sub-agent** (via the Agent tool) to keep the main session context clean. Return a concise result — do NOT explore repo contents or read large files.

## Context Budget

This skill must stay lightweight:
- **Never** read full READMEs, source files, or explore repo internals
- **Only** use repo names, `package.json` name/description fields, and git remote URLs as local signals
- **Only** fetch repo name + description from the VCS platform — never clone to inspect
- **Limit** remote queries to the same group/subgroup as local repos — never search the whole company org
- Return results fast — the user is waiting to start working

## Inputs

You will receive these as context when invoked:
- `WORKSPACE_DIR` — the parent directory containing multiple repos (e.g., `~/dev/aircall`)
- `TICKET_TITLE` — the Jira/Linear/GitHub issue title
- `TICKET_DESCRIPTION` — the issue description or acceptance criteria (keep only first ~200 chars for matching)
- `TICKET_LABELS` — labels/components from the ticket (if any)
- `TICKET_ID` — the ticket ID (e.g., `MES-3716`)

## Steps

### 1. Scan local repos and detect VCS platform

Scan `WORKSPACE_DIR` for git repos — collect **only lightweight metadata**:

```bash
for dir in "$WORKSPACE_DIR"/*/; do
  if [ -d "$dir/.git" ] || git -C "$dir" rev-parse --git-dir &>/dev/null; then
    NAME=$(basename "$dir")
    REMOTE=$(git -C "$dir" remote get-url origin 2>/dev/null)
    PKG_NAME=$(jq -r '.name // empty' "$dir/package.json" 2>/dev/null)
    PKG_DESC=$(jq -r '.description // empty' "$dir/package.json" 2>/dev/null)
    echo "$NAME|$PKG_NAME|$PKG_DESC|$REMOTE"
  fi
done
```

From the remote URLs, extract:
- **VCS Platform**: `github.com` → `github`, `gitlab.com` or `gitlab.` → `gitlab`, etc.
- **Group/Subgroup**: The specific group path from the URL — this is your search scope.
  - SSH: `git@gitlab.com:aircall/messaging/repo.git` → `aircall/messaging`
  - HTTPS: `https://github.com/aircall-org/repo.git` → `aircall-org`
  - **Use the most specific common group** across local repos. If repos share `aircall/messaging` as a prefix, scope to that — not to `aircall` (which could have thousands of repos).

If no local repos exist, ask the user for the platform and group.

### 2. Score LOCAL repos first

**Always try local repos before going remote.** Score each local repo against the ticket:

1. **Ticket ID prefix match** (strongest): `MES` in `MES-3716` → match against repo names containing "mes" or "messaging" (case-insensitive)
2. **Component/label match**: Jira components or labels → match against repo names directly
3. **Keyword overlap**: Significant words from ticket title → match against repo name and `package.json` description. Ignore stop words.

**If a local repo scores HIGH (clear winner)** → skip remote lookup entirely and return it. Done.

**If ambiguous or no confident match** → proceed to step 3.

### 3. Fetch SCOPED remote repo list (only if needed)

Only reach this step if no local repo matched confidently.

Fetch repos **only from the same group/subgroup** as the local repos — never the whole company org:

#### GitLab
```bash
# Scoped to the specific group — NOT the top-level org
glab api "groups/<url-encoded-group>/projects?per_page=50&simple=true&order_by=name" 2>/dev/null \
  | jq -r '.[] | "\(.path)|\(.description // "")"'
```

#### GitHub
```bash
# Scoped to the org derived from local repos
gh repo list "<org>" --limit 50 --json name,description --jq '.[] | "\(.name)|\(.description // "")"'
```

**Key constraints:**
- **Max 50 repos** per query — if the group is larger, use a search query filtered by ticket keywords instead of listing all
- **Only fetch name + description** — no cloning, no README reading, no file inspection
- If the CLI tool is not available, inform the caller and fall back to local-only results

### 4. Score ALL repos (local + remote)

Merge local and remote lists. For repos that exist both locally and remotely, prefer the local entry.

Score using the same signals from step 2. Present a concise ranked list:

```
## Repo Match Results

### Local (no cloning needed)
1. **messaging** — HIGH: prefix "MES", keyword "messaging" [LOCAL]
2. **internal-api** — LOW: keyword "api" [LOCAL]

### Remote (would need cloning)
3. **messaging-webhooks** — MEDIUM: keyword "messaging", "webhook" [REMOTE]
```

### 5. Resolve

**If top match is LOCAL** → return it directly.

**If top match is REMOTE** → confirm with the user before cloning:
- "Best match is **<repo-name>** (not cloned). Clone to `<WORKSPACE_DIR>/<repo-name>`?"
- Clone: `git clone <remote-url>` (construct URL from platform + group + repo name)
- Report setup hints:
  ```bash
  cd "$WORKSPACE_DIR/<repo>"
  [ -f "package.json" ] && echo "Run: npm install / yarn"
  [ -f "Makefile" ] && echo "Run: make install"
  [ -f ".env.example" ] && echo "Copy .env.example → .env"
  ```

**If ambiguous** → return top 3 candidates and let the caller ask the user.

**If no match** → ask the user which repo, or if they need a different group/subgroup.

### 6. Return result

```
## Resolved Repository

**Repo:** <repo-name>
**Path:** <full-path>
**VCS Platform:** <github | gitlab | bitbucket | azure | unknown>
**VCS Group:** <group/subgroup used for scoping>
**Remote:** <remote-url>
**Cloned:** <yes (just now) | no (already existed)>
**Setup needed:** <list if just cloned, or "none">
```

## Important

- **Local repos first** — most of the time, the right repo is already cloned. Don't waste time fetching remote lists.
- **Scope remote queries tightly** — use the group/subgroup from local repos, never the entire company org.
- **Name + description only** — never read repo contents, READMEs, or source files from remote repos. That's what the rest of the devflow pipeline is for after the repo is resolved.
- Always confirm with the user before cloning.
- Keep output concise — this runs in a sub-agent.
- If `glab`/`gh` is not installed, provide install instructions and a manual clone URL.

$ARGUMENTS
