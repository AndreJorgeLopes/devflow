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

# ensure_docker — check Docker daemon is running
ensure_docker() {
  need_cmd docker
  timeout 5 docker info >/dev/null 2>&1 || die "Docker is not running. Start your Docker runtime (e.g. colima start, or start Docker Desktop)."
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
