---
description: [0.27.3] Resolve the correct repository for a task — detect VCS platform, match ticket to repo, clone if missing. Run this in a sub-agent to avoid filling main context.
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

## Determinism (offload to the shared lib; AI only on abstain)

Source the determinism-fix lib once before your bash work:

```bash
for f in ~/.claude/lib/determinism/functions/*.sh; do . "$f"; done
```

These functions are **sound, not complete** (see `~/.claude/lib/determinism/CONTRACT.md`):
they return a value (exit `0`) only for unambiguous input and **abstain (exit `10`) /
error (exit `1`)** otherwise. Use them deterministic-first; fall back to model judgment
ONLY on a non-zero exit — never as a second opinion on a confident answer:

```bash
val=$(detect_vcs_platform "$REMOTE") || val=""   # empty ⇒ lib abstained ⇒ you infer it
```

Used in this skill: `detect_vcs_platform`, `extract_repo_group`, `extract_ticket_id`.
**Do NOT determinize the repo SCORING / ranking** (Steps 2 & 4) — that is judgment and a
deterministic version is confidently worse; keep it model-driven and only pin its OUTPUT
format (Steps 4 & 6).

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

From each remote URL, extract platform + group **with the lib** (D1, D2 — deterministic,
abstain→AI). Do NOT classify the host or "judge the group" in prose:

```bash
PLATFORM=$(detect_vcs_platform "$REMOTE") || PLATFORM=""   # github|gitlab|bitbucket|azure ; "" ⇒ abstained (unknown/self-hosted)
GROUP=$(extract_repo_group "$REMOTE")     || GROUP=""      # e.g. aircall/messaging ; "" ⇒ abstained (no group segment)
```

- If `PLATFORM` is empty (lib abstained on an unknown/self-hosted host), THEN infer it
  yourself from the URL — that is the only case AI runs.
- **Group/Subgroup scope** = the **longest common path-prefix** of the non-empty
  `GROUP`s across local repos (deterministic — compute it, don't judge "most specific").
  If repos share `aircall/messaging`, scope to that, not `aircall`. If the common prefix
  is empty or the repos diverge at the org root, fall back to asking the user.

If no local repos exist, ask the user for the platform and group.

### 2. Score LOCAL repos first

**Always try local repos before going remote.** Score each local repo against the ticket:

1. **Ticket ID prefix match** (strongest): extract the prefix deterministically (D3) —
   `ID=$(extract_ticket_id "$TICKET_ID") || ID="$TICKET_ID"; PREFIX="${ID%%-*}"` — then
   case-insensitive substring-match `PREFIX` against repo names. No hand-coded synonym list.
2. **Component/label match**: ticket components/labels → substring-match repo names directly.
3. **Keyword overlap**: significant title words → match repo name + `package.json` description.
   Drop stop words with a FIXED list (D5), not by judgment:
   `the|a|an|for|in|on|of|to|and|or|with|is|are|fix|add|update|support`.

**Scoring stays model-driven (judgment — do NOT determinize: a fixed weight table is
confidently worse here).** Weigh the signals and assign each repo a band, but emit ONLY the
pinned labels **`HIGH` / `MEDIUM` / `LOW`** — never qualifiers ("probably", "likely",
"confident"). A HIGH local match (clear winner) skips the remote lookup in step 3 — but it
does NOT skip the Repo Match Results block: you ALWAYS emit that block (step 4) before
resolving, listing the local candidates only. An ambiguous / no-confident match → step 3.

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

### 4. Score ALL repos (local + remote) — ALWAYS emit this block

This block is **always emitted**, before the Resolved Repository block — including when step 2
found a clear HIGH local winner and step 3 was skipped (in that case list only the local
candidates). Merge local and remote lists; for repos that exist both locally and remotely, prefer the local entry.

Score using the same signals from step 2. **Order deterministically (D7):** sort by band
(HIGH → MEDIUM → LOW), then alphabetically by repo name within a band. Emit EXACTLY this
block (D6). These rules are mandatory — the output is machine-checked:

- Output ONLY the block. No prose before or after it (no "Looking at…", no "Highest match is…"), no markdown fences. The chosen repo goes in the separate Resolved Repository block in step 5, not here.
- Each line is exactly `N. **<name>** — <BAND>: <reasons> [<TAG>]`.
- `<BAND>` is one of `HIGH` / `MEDIUM` / `LOW`, written **bare and immediately followed by a colon** — `HIGH:` not `**HIGH**:`, never a synonym or qualifier.
- Every line MUST end with the source tag `[LOCAL]` or `[REMOTE]`. Never omit it.
- Keep the `### Local` / `### Remote` sub-headers.

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

Emit EXACTLY this block (D9) — these fields, in this order; output ONLY the block, no
leading/trailing prose, no markdown fences. `VCS Platform` ∈ {github, gitlab, bitbucket,
azure, unknown}; `Cloned` ∈ {yes (just now), no (already existed)}:

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
