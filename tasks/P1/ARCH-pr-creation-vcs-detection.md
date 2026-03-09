---
id: ARCH-pr-creation-vcs-detection
title: "PR Creation With Correct VCS Tool"
priority: P1
category: architecture
status: done
depends_on: []
estimated_effort: S
files_to_touch:
  - skills/pr-pipeline/create-pr.md
  - skills/worktree-flow/finish-feature.md
  - lib/utils.sh
---

# PR Creation With Correct VCS Tool

## Context

The `create-pr` skill and `finish-feature` skill currently hardcode `gh pr create` (GitHub CLI) for pull request creation. This works for GitHub-hosted repositories but breaks for projects hosted on GitLab, Bitbucket, Azure DevOps, or other VCS providers. Devflow should be VCS-agnostic.

## Problem Statement

1. Skills hardcode `gh pr create` — fails on non-GitHub repos
2. No detection logic exists to determine the VCS provider from the git remote
3. No fallback when the required CLI tool (gh, glab, etc.) isn't installed
4. Each skill independently implements PR creation instead of using a shared approach

## Desired Outcome

- PR creation in all skills automatically uses the correct CLI tool based on the git remote
- VCS detection is centralized (one function, used everywhere)
- Clear error messages when the required CLI tool isn't installed
- Supported providers: GitHub (`gh`), GitLab (`glab`), with extensibility for others

## Implementation Guide

### Step 1: Create VCS detection utility

Add to `lib/utils.sh` (or create it if it doesn't exist):

```bash
# Detect VCS provider from git remote URL
# Returns: github, gitlab, bitbucket, azure, or unknown
detect_vcs_provider() {
  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || echo "")"

  if [[ -z "$remote_url" ]]; then
    echo "unknown"
    return 1
  fi

  case "$remote_url" in
    *github.com*)     echo "github" ;;
    *gitlab.com*|*gitlab.*)  echo "gitlab" ;;
    *bitbucket.org*)  echo "bitbucket" ;;
    *dev.azure.com*|*visualstudio.com*)  echo "azure" ;;
    *)                echo "unknown" ;;
  esac
}

# Get the CLI tool name for PR creation
# Returns the command name or errors if not installed
get_vcs_cli() {
  local provider
  provider="$(detect_vcs_provider)"

  case "$provider" in
    github)
      if command -v gh &>/dev/null; then
        echo "gh"
      else
        echo "ERROR: GitHub CLI (gh) not installed. Install: brew install gh" >&2
        return 1
      fi
      ;;
    gitlab)
      if command -v glab &>/dev/null; then
        echo "glab"
      else
        echo "ERROR: GitLab CLI (glab) not installed. Install: brew install glab" >&2
        return 1
      fi
      ;;
    bitbucket)
      echo "ERROR: Bitbucket CLI not supported. Create PR manually." >&2
      return 1
      ;;
    azure)
      if command -v az &>/dev/null; then
        echo "az"
      else
        echo "ERROR: Azure CLI (az) not installed. Install: brew install azure-cli" >&2
        return 1
      fi
      ;;
    *)
      echo "ERROR: Unknown VCS provider. Create PR manually." >&2
      return 1
      ;;
  esac
}

# Create a PR/MR using the correct CLI tool
# Usage: create_pr "title" "body" [base_branch]
create_pr() {
  local title="$1"
  local body="$2"
  local base="${3:-}"  # optional base branch
  local provider
  provider="$(detect_vcs_provider)"

  case "$provider" in
    github)
      gh pr create --title "$title" --body "$body" ${base:+--base "$base"}
      ;;
    gitlab)
      glab mr create --title "$title" --description "$body" ${base:+--target-branch "$base"}
      ;;
    azure)
      az repos pr create --title "$title" --description "$body" ${base:+--target-branch "$base"}
      ;;
    *)
      echo "Cannot auto-create PR for provider: $provider" >&2
      echo "Please create the PR manually." >&2
      return 1
      ;;
  esac
}
```

### Step 2: Update `create-pr` skill

In `skills/pr-pipeline/create-pr.md`, replace hardcoded `gh` references with VCS-aware instructions:

````markdown
## Creating the Pull Request

Detect the VCS provider from the git remote URL:

1. Get the remote URL: `git remote get-url origin`
2. Determine the provider:
   - Contains `github.com` → use `gh pr create`
   - Contains `gitlab.com` or `gitlab.` → use `glab mr create`
   - Other → tell the developer to create the PR manually

### GitHub (gh)

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<bullet points>
EOF
)"
```
````

### GitLab (glab)

```bash
glab mr create --title "<title>" --description "$(cat <<'EOF'
## Summary
<bullet points>
EOF
)"
```

### Unsupported provider

If the provider is not recognized:

1. Push the branch: `git push -u origin HEAD`
2. Output the URL the developer should visit to create the PR manually
3. For GitHub-like: `https://<host>/<org>/<repo>/compare/<branch>`

````

### Step 3: Update `finish-feature` skill

In `skills/worktree-flow/finish-feature.md`, apply the same VCS-aware pattern. Replace any instance of `gh pr create` with the detection-first approach from Step 2.

### Step 4: Verify CLI tool availability in `devflow init`

During `devflow init`, detect the VCS provider and check that the corresponding CLI tool is installed:

```bash
# In lib/init.sh
check_vcs_tool() {
  local provider
  provider="$(detect_vcs_provider)"

  case "$provider" in
    github)
      if ! command -v gh &>/dev/null; then
        echo "WARNING: GitHub CLI (gh) not installed."
        echo "  Install: brew install gh"
        echo "  Without it, PR creation will be manual."
      fi
      ;;
    gitlab)
      if ! command -v glab &>/dev/null; then
        echo "WARNING: GitLab CLI (glab) not installed."
        echo "  Install: brew install glab"
        echo "  Without it, MR creation will be manual."
      fi
      ;;
  esac
}
````

## Acceptance Criteria

- [ ] `detect_vcs_provider` correctly identifies GitHub, GitLab, and returns "unknown" for others
- [ ] Skills (`create-pr.md`, `finish-feature.md`) no longer hardcode `gh pr create`
- [ ] For a GitHub repo, the agent uses `gh pr create`
- [ ] For a GitLab repo, the agent uses `glab mr create`
- [ ] For an unknown provider, the agent gives clear manual instructions
- [ ] `lib/utils.sh` contains the `detect_vcs_provider`, `get_vcs_cli`, and `create_pr` functions
- [ ] `devflow init` warns if the VCS CLI tool is not installed
- [ ] The `done.md` skill (ARCH-P1-007) can use VCS detection for its PR creation step

## Technical Notes

- **SSH vs HTTPS remotes**: `git remote get-url origin` may return either format:
  - SSH: `git@github.com:org/repo.git`
  - HTTPS: `https://github.com/org/repo.git`
    Both should match the same provider. The `case` pattern `*github.com*` handles both.

- **Multiple remotes**: Some repos have multiple remotes (origin, upstream). Always use `origin` as the canonical remote for VCS detection.

- **Self-hosted GitLab**: The pattern `*gitlab.*` catches self-hosted instances (e.g., `gitlab.company.com`). This is intentionally broad. If false positives occur, it can be narrowed.

- **`glab` authentication**: `glab` requires authentication via `glab auth login`. If auth fails, the error message should point the developer to authenticate, not just say "failed."

- **PR vs MR terminology**: GitHub uses "Pull Request" (PR), GitLab uses "Merge Request" (MR). The skills should use the correct terminology based on the detected provider.

- **Base branch detection**: The `create_pr` function accepts an optional base branch. If not provided, both `gh` and `glab` default to the repo's default branch (usually `main` or `master`).

## Verification

```bash
# 1. Test detection with a GitHub repo
cd ~/dev/some-github-project
source /Users/andrejorgelopes/dev/devflow/lib/utils.sh
detect_vcs_provider
# Expected: "github"

# 2. Test detection with a GitLab repo (if available)
cd ~/dev/some-gitlab-project
detect_vcs_provider
# Expected: "gitlab"

# 3. Test CLI availability
get_vcs_cli
# Expected: "gh" (for GitHub) or error message with install instructions

# 4. Test in skills (manual verification)
# In a GitHub repo, trigger the create-pr skill
# Expected: uses `gh pr create`
# In a GitLab repo, trigger the create-pr skill
# Expected: uses `glab mr create`

# 5. Test unknown provider
cd /tmp && git init test-unknown && cd test-unknown
git remote add origin https://custom-git.example.com/repo.git
source /Users/andrejorgelopes/dev/devflow/lib/utils.sh
detect_vcs_provider
# Expected: "unknown"
get_vcs_cli
# Expected: error message about unknown provider

# 6. Cleanup
rm -rf /tmp/test-unknown
```
