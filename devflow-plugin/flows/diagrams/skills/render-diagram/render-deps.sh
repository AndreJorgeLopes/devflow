#!/usr/bin/env bash
# devflow/lib/render-deps.sh — resolve the 3 Excalidraw-render npm deps without `devflow init`.
#
# Resolution order: existing globals → ~/.devflow/render-deps cache → consent + local install
# (`npm install --prefix <cache>`, no `-g`, no sudo). Echoes the resolved node_modules-parent
# dir on STDOUT (caller sets NODE_PATH + EXCAL_NODE_MODULES to it). All progress/prompt noise
# goes to STDERR so command substitution captures only the path.
#
# Bundled byte-identically into the devflow-diagrams flow so render works without bin/devflow.

RENDER_PKGS="canvas@3 excalidraw-to-svg @resvg/resvg-js"   # canvas@3+ for Node >=25 (canvas@2 has no node-25 prebuilt)
RENDER_PKG_DIRS="canvas excalidraw-to-svg @resvg/resvg-js"

# _render_deps_have <node_modules-dir> → 0 if all 3 package dirs present, else 1.
_render_deps_have() {
  local nm="$1" d
  for d in $RENDER_PKG_DIRS; do
    [[ -d "${nm}/${d}" ]] || return 1
  done
  return 0
}

# render_deps_resolve → echoes the node_modules dir to use; returns non-zero if unresolved.
render_deps_resolve() {
  local cache="${DEVFLOW_RENDER_CACHE:-$HOME/.devflow/render-deps}"

  # 1) Existing globals (current behavior — fast path).
  local gm; gm="$(npm root -g 2>/dev/null || echo "")"
  if [[ -n "$gm" ]] && _render_deps_have "$gm"; then
    echo "$gm"; return 0
  fi

  # 2) Local cache from a previous resolve.
  if _render_deps_have "${cache}/node_modules"; then
    echo "${cache}/node_modules"; return 0
  fi

  # 3) Consent, then install locally into the cache (no -g, no sudo).
  #    Skills gate consent via AskUserQuestion and pass DEVFLOW_RENDER_ASSUME_YES=1; the
  #    interactive read here is only a human-CLI fallback (EOFs to "n" in a non-TTY run).
  if [[ "${DEVFLOW_RENDER_ASSUME_YES:-0}" != "1" ]]; then
    printf 'Render deps (%s) not found. Install into %s now? [y/N] ' "$RENDER_PKGS" "$cache" >&2
    local ans; read -r ans || ans="n"
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo "render deps not installed (declined)" >&2; return 1 ;;
    esac
  fi

  mkdir -p "$cache"
  # shellcheck disable=SC2086  # intentional word-split: RENDER_PKGS is 3 separate args
  npm install --prefix "$cache" $RENDER_PKGS >&2 || { echo "npm install failed" >&2; return 1; }
  _render_deps_have "${cache}/node_modules" || { echo "render deps still missing after install" >&2; return 1; }
  echo "${cache}/node_modules"
}
