#!/usr/bin/env bash
# Standalone render launcher (no bin/devflow): resolve deps + run the bundled export.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "${here}/render-deps.sh"
nm="$(render_deps_resolve)"
NODE_PATH="$nm" EXCAL_NODE_MODULES="$nm" node "${here}/excalidraw-export.cjs" "$@"
