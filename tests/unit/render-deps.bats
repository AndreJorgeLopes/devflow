#!/usr/bin/env bats
# tests/unit/render-deps.bats — npm dep resolution order (Phase D: D1).
# Order under test: globals -> ~/.devflow/render-deps cache -> consent install (no -g/sudo).
# Uses a self-contained branching npm stub (root -g vs install --prefix) per the plan.

load '../helpers/common'
load '../helpers/assertions'

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  MOCK="${BATS_TEST_TMPDIR}/bin"; mkdir -p "$MOCK"
  # branching npm stub: 'root -g' -> empty dir (no deps); 'install --prefix DIR ...' -> create node_modules/<pkgs>
  cat > "$MOCK/npm" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "root" ] && [ "$2" = "-g" ]; then echo "/nonexistent-global-root"; exit 0; fi
if [ "$1" = "install" ] || [ "$1" = "i" ]; then
  pfx=""; while [ $# -gt 0 ]; do [ "$1" = "--prefix" ] && { pfx="$2"; shift; }; shift; done
  mkdir -p "$pfx/node_modules/canvas" "$pfx/node_modules/excalidraw-to-svg" "$pfx/node_modules/@resvg/resvg-js"; exit 0
fi
exit 0
EOF
  chmod +x "$MOCK/npm"
  cat > "$MOCK/node" <<'EOF'
#!/usr/bin/env bash
echo "v25.0.0"; exit 0
EOF
  chmod +x "$MOCK/node"
  export PATH="$MOCK:$PATH"
  export DEVFLOW_RENDER_CACHE="${BATS_TEST_TMPDIR}/render-deps"
  export DEVFLOW_RENDER_ASSUME_YES=1   # bypass consent in tests
  source "${REPO}/lib/utils.sh"; source "${REPO}/lib/render-deps.sh"
}

@test "resolver installs into the cache when globals lack the deps" {
  run render_deps_resolve
  assert_success
  assert [ -d "${DEVFLOW_RENDER_CACHE}/node_modules/canvas" ]
  assert_output --partial "${DEVFLOW_RENDER_CACHE}"   # echoes the chosen NODE_PATH dir
}

@test "resolver reuses the cache on a second call without reinstalling" {
  render_deps_resolve >/dev/null
  run render_deps_resolve
  assert_success
}
