#!/usr/bin/env bash
# promptfoo `exec:` provider for this skill's determinism asserts (dev-only; excluded from the plugin).
# Read-only skill: no DEVFLOW_EVAL, runs from the repo root so it can read the fixture doc.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${here}/../../eval/lib/run-skill.sh" "$@"
