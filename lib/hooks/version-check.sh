#!/usr/bin/env bash
# devflow/lib/hooks/version-check.sh
# Claude Code SessionStart hook — warns when the installed devflow is behind the latest
# release on origin, so a stale install (e.g. a maintainer stuck in local dev mode, or an
# end user who hasn't pulled the auto-updated plugin) is visible instead of silently
# serving old skills/commands.
#
# Protocol (SessionStart): exit 0 + stdout → stdout is injected as session context.
# This hook is ALWAYS non-blocking and fail-silent: any error / no network / no tools →
# exit 0 with no output. It never slows or blocks a session.
#
# Network cost is bounded: one `git ls-remote` with a short timeout, and the result is
# cached for the day so it runs at most once per calendar day per machine.

set +e

REPO_URL="https://github.com/AndreJorgeLopes/devflow.git"
CACHE_DIR="${HOME}/.devflow"
CACHE_FILE="${CACHE_DIR}/version-check.cache"   # format: "<YYYY-MM-DD> <latest-tag>"

# --- installed version (fail-silent if devflow CLI absent) ---
command -v devflow >/dev/null 2>&1 || exit 0
installed="$(devflow version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[ -n "$installed" ] || exit 0
installed="${installed#v}"

today="$(date +%Y-%m-%d 2>/dev/null)" || exit 0

# --- resolve latest release tag, using a daily cache to avoid repeat network calls ---
latest=""
if [ -f "$CACHE_FILE" ]; then
  read -r cached_date cached_tag < "$CACHE_FILE" 2>/dev/null
  [ "$cached_date" = "$today" ] && latest="$cached_tag"
fi

if [ -z "$latest" ]; then
  # Newest semver tag on origin. `--sort=-v:refname` puts the highest version first.
  latest="$(timeout 5 git ls-remote --tags --refs --sort=-v:refname "$REPO_URL" 'v[0-9]*' 2>/dev/null \
             | head -1 | sed -E 's#.*refs/tags/##')"
  # Network/tool failure → skip silently (do not warn on a value we could not fetch).
  [ -n "$latest" ] || exit 0
  mkdir -p "$CACHE_DIR" 2>/dev/null
  printf '%s %s\n' "$today" "$latest" > "$CACHE_FILE" 2>/dev/null
fi
latest="${latest#v}"

# --- compare (semver via sort -V); only warn when installed is strictly behind ---
[ "$installed" = "$latest" ] && exit 0
lowest="$(printf '%s\n%s\n' "$installed" "$latest" | sort -V 2>/dev/null | head -1)"
# If installed is NOT the lowest, we are at or ahead of latest → nothing to say.
[ "$lowest" = "$installed" ] || exit 0

cat <<EOF
[devflow] Installed version v${installed} is behind the latest release v${latest} on origin.
Update to pick up merged skills/commands:
  - GitHub-source install (default): the plugin auto-updates on session start; if it hasn't, run \`claude plugin update devflow@devflow-marketplace\` (or re-run \`devflow init\`), and \`git -C ~/dev/devflow pull\` + \`make -C ~/dev/devflow install\` for the CLI.
  - Local dev mode (\`make plugin-dev\`): \`git pull\` your devflow clone and re-run \`make plugin-dev\` / \`make install\`.
EOF
exit 0
