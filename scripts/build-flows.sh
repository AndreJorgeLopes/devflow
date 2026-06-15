#!/usr/bin/env bash
# scripts/build-flows.sh — generate per-flow mini-plugins from canonical sources.
#
# Flows are a GENERATED 4th copy of each skill; never hand-edit devflow-plugin/flows/.
# Canonical source stays devflow-plugin/{commands,skills}. The flow→skills map lives in
# scripts/flows.manifest (pipe-delimited, bash-3.2-safe — no associative arrays).
#
# Each flows/<flow>/ is a self-contained mini-plugin: own .claude-plugin/plugin.json
# (name devflow-<flow>, version synced with the full plugin), commands/, and skills/
# (incl. requirements.json + bundle files), all copied byte-identically from canonical.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="${ROOT}/devflow-plugin"
MANIFEST="${ROOT}/scripts/flows.manifest"

command -v jq >/dev/null 2>&1 || { echo "build-flows: jq is required" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "build-flows: missing $MANIFEST" >&2; exit 1; }

VERSION="$(jq -r .version "${PLUGIN}/.claude-plugin/plugin.json")"

# `|| [[ -n "$flow" ]]` keeps the last manifest line even without a trailing newline.
while IFS='|' read -r flow skills || [[ -n "$flow" ]]; do
  # Skip blank lines and comments.
  case "$flow" in ''|\#*) continue ;; esac
  flow="$(echo "$flow" | tr -d '[:space:]')"
  [[ -n "$flow" ]] || continue

  outdir="${PLUGIN}/flows/${flow}"
  rm -rf "$outdir"
  mkdir -p "${outdir}/.claude-plugin" "${outdir}/commands" "${outdir}/skills"

  # Per-flow plugin.json (skills/ auto-discovered; commands explicit).
  printf '{\n  "name": "devflow-%s",\n  "description": "devflow %s flow",\n  "version": "%s",\n  "author": {\n    "name": "Andre Jorge Lopes"\n  },\n  "commands": "./commands/"\n}\n' \
    "$flow" "$flow" "$VERSION" > "${outdir}/.claude-plugin/plugin.json"

  # Copy each skill (command + skill dir incl. requirements.json + bundle files).
  # Intentional word-split on the comma→space list (bash-3.2-safe, no arrays).
  skill_list="$(echo "$skills" | tr ',' ' ')"
  for sk in $skill_list; do
    sk="$(echo "$sk" | tr -d '[:space:]')"
    [[ -n "$sk" ]] || continue
    [[ -d "${PLUGIN}/skills/${sk}" ]] || { echo "build-flows: unknown skill '$sk' in flow '$flow'" >&2; exit 1; }
    [[ -f "${PLUGIN}/commands/${sk}.md" ]] || { echo "build-flows: missing command for skill '$sk'" >&2; exit 1; }
    cp "${PLUGIN}/commands/${sk}.md" "${outdir}/commands/${sk}.md"
    cp -R "${PLUGIN}/skills/${sk}" "${outdir}/skills/${sk}"
  done

  echo "built flow: ${flow} (${skills})"
done < "$MANIFEST"
