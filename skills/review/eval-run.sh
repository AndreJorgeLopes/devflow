#!/usr/bin/env bash
# promptfoo `exec:` provider for this skill's determinism asserts.
# promptfoo runs the exec command from THIS config's directory and validates the file
# locally, so it must be a local file — it then execs the shared headless runner with an
# absolute path (no CWD assumptions). Dev-only: excluded from the shipped plugin.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${here}/../../eval/lib/run-skill.sh" "$@"
