#!/usr/bin/env bash
# devflow/lib/utils.sh — Shared utilities
# Sourced by all other lib files and the main CLI entry point.

DEVFLOW_VERSION="0.1.0"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
log()  { printf "${GREEN}[devflow]${RESET} %s\n" "$*"; }
info() { printf "${BLUE}[devflow]${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}[devflow]${RESET} %s\n" "$*" >&2; }
err()  { printf "${RED}[devflow]${RESET} %s\n" "$*" >&2; }
die()  { err "$@"; exit 1; }

# Bold section header
section() { printf "\n${BOLD}${CYAN}── %s ──${RESET}\n" "$*"; }

# Dim detail line
detail() { printf "  ${DIM}%s${RESET}\n" "$*"; }

# Status indicators
ok()   { printf "  ${GREEN}✓${RESET} %s\n" "$*"; }
fail() { printf "  ${RED}✗${RESET} %s\n" "$*"; }
skip() { printf "  ${YELLOW}⊘${RESET} %s\n" "$*"; }

# ── Checks ────────────────────────────────────────────────────────────────────

# need_cmd <cmd> — die if command is not available
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# has_cmd <cmd> — return 0/1 without dying
has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# ensure_docker — check Docker CLI exists and daemon is reachable
ensure_docker() {
  # 1. Check Docker CLI is installed
  if ! has_cmd docker; then
    die "Docker CLI not found. Install from https://docs.docker.com/get-docker/"
  fi

  # 2. Check daemon is reachable
  if timeout 5 docker info >/dev/null 2>&1; then
    return 0
  fi

  # 3. Daemon unreachable — detect available runtimes and suggest accordingly
  local runtimes=()
  has_cmd colima          && runtimes+=("colima start")
  [[ -d "/Applications/Docker.app" ]] && runtimes+=("open -a Docker")
  has_cmd orbctl          && runtimes+=("orbctl start")

  if [[ ${#runtimes[@]} -gt 0 ]]; then
    local suggestions
    suggestions=$(printf "'%s'" "${runtimes[0]}")
    for ((i=1; i<${#runtimes[@]}; i++)); do
      suggestions+=", or '${runtimes[$i]}'"
    done
    die "Docker daemon is not running. Start it with: ${suggestions}"
  else
    die "Docker daemon is not running and no runtime found. Install one of: colima (brew install colima) or Docker Desktop (https://docs.docker.com/get-docker/)"
  fi
}

# ── Paths ─────────────────────────────────────────────────────────────────────

# devflow_root — directory where devflow itself is installed (parent of bin/)
devflow_root() {
  local script_dir
  # Resolve symlinks to find the real install location
  if [[ -L "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" ]]; then
    script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")")" && pwd)"
  else
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
  fi
  # Walk up from bin/ or lib/ to the devflow root
  case "$script_dir" in
    */bin) dirname "$script_dir" ;;
    */lib) dirname "$script_dir" ;;
    *)     echo "$script_dir" ;;
  esac
}

# project_root — return the git root of the current working directory
project_root() {
  local dir="${1:-$(pwd)}"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null \
    || die "Not inside a git repository: $dir"
}

# ── Docker Compose ────────────────────────────────────────────────────────────

# docker_compose — return the correct compose command (plugin vs standalone)
docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif has_cmd docker-compose; then
    docker-compose "$@"
  else
    die "Neither 'docker compose' nor 'docker-compose' found."
  fi
}

# Path to the devflow docker-compose file
devflow_compose_file() {
  echo "$(devflow_root)/docker/docker-compose.yml"
}

# ── Hindsight API ─────────────────────────────────────────────────────────────
HINDSIGHT_API="${HINDSIGHT_API:-http://localhost:8888}"

# hindsight_post <endpoint> <json_body>
hindsight_post() {
  local endpoint="$1" body="$2"
  curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "$body" \
    "${HINDSIGHT_API}${endpoint}" 2>/dev/null
}

# hindsight_available — check if Hindsight API is reachable
hindsight_available() {
  curl -sf -o /dev/null "${HINDSIGHT_API}/health" 2>/dev/null
}

# ── VCS Detection ─────────────────────────────────────────────────────────────

# detect_vcs_provider — Detect VCS provider from git remote URL
# Returns: github, gitlab, bitbucket, azure, or unknown
detect_vcs_provider() {
  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || echo "")"

  if [[ -z "$remote_url" ]]; then
    echo "unknown"
    return 1
  fi

  case "$remote_url" in
    *github.com*)                        echo "github" ;;
    *gitlab.com*|*gitlab.*)              echo "gitlab" ;;
    *bitbucket.org*)                     echo "bitbucket" ;;
    *dev.azure.com*|*visualstudio.com*)  echo "azure" ;;
    *)                                   echo "unknown" ;;
  esac
}

# get_vcs_pr_term — Return the correct term for a PR based on provider
# Returns: PR (GitHub/generic), MR (GitLab)
get_vcs_pr_term() {
  local provider
  provider="$(detect_vcs_provider)"
  case "$provider" in
    gitlab) echo "MR" ;;
    *)      echo "PR" ;;
  esac
}

# ── Merge Detection ──────────────────────────────────────────────────────────

# is_branch_merged <main_branch> <feature_branch>
# Returns 0 if the feature branch is fully merged (or squash-merged) into main.
# 3-layer detection:
#   1. rev-list: 0 commits ahead → merged
#   2. merge-tree: identical tree after merge → content-equivalent (squash)
#   3. VCS CLI: check if PR/MR was merged on the remote
is_branch_merged() {
  local main_branch="$1" feature_branch="$2"

  # Layer 1: rev-list — if 0 commits ahead, it's a normal merge
  local ahead
  ahead="$(git rev-list --count "${main_branch}..${feature_branch}" 2>/dev/null || echo "")"
  if [[ "$ahead" == "0" ]]; then
    return 0
  fi

  # Layer 2: merge-tree — if merging produces same tree as main, content is equivalent
  if [[ -n "$ahead" ]]; then
    local merge_tree_out
    if merge_tree_out="$(git merge-tree --write-tree --no-messages "$main_branch" "$feature_branch" 2>/dev/null)"; then
      local main_tree
      main_tree="$(git rev-parse "${main_branch}^{tree}" 2>/dev/null || echo "")"
      if [[ -n "$main_tree" ]] && [[ "$merge_tree_out" == "$main_tree" ]]; then
        return 0
      fi
    fi
    # merge-tree conflict or unsupported → fall through
  fi

  # Layer 3: VCS CLI — check if PR/MR was merged on the remote
  local provider
  provider="$(detect_vcs_provider)"
  case "$provider" in
    github)
      if has_cmd gh; then
        local merged_count
        merged_count="$(gh pr list --head "$feature_branch" --state merged --json number --jq 'length' 2>/dev/null || echo "")"
        if [[ -n "$merged_count" ]] && [[ "$merged_count" -gt 0 ]]; then
          return 0
        fi
      fi
      ;;
    gitlab)
      if has_cmd glab; then
        local mr_output
        mr_output="$(glab mr list --source-branch "$feature_branch" --merged 2>/dev/null || echo "")"
        if [[ -n "$mr_output" ]] && [[ "$mr_output" != *"No merge requests"* ]]; then
          return 0
        fi
      fi
      ;;
  esac

  return 1
}
