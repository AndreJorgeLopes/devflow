#!/usr/bin/env bash
# scripts/bump-version.sh — Standalone version bump script
# Usage: scripts/bump-version.sh <new_version> [project_dir]
# Updates all version-bearing files to the specified version.
# Used by both GitHub Actions and local CLI (devflow version-bump).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVFLOW_ROOT="$(dirname "$SCRIPT_DIR")"

source "${DEVFLOW_ROOT}/lib/utils.sh"
source "${DEVFLOW_ROOT}/lib/release.sh"

new_version="${1:?Usage: bump-version.sh <new_version> [project_dir]}"
project_dir="${2:-$DEVFLOW_ROOT}"

bump_all_versions "$new_version" "$project_dir"

# Validate consistency after bump
source "${DEVFLOW_ROOT}/lib/watch.sh"
check_version_consistency "$project_dir"
