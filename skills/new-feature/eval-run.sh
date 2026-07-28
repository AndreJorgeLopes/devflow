#!/usr/bin/env bash
# promptfoo `exec:` provider for this skill's determinism asserts (dev-only; excluded from the plugin).
# This skill has SIDE EFFECTS, so set DEVFLOW_EVAL=1: the shared runner then isolates it in a
# throwaway git fixture (no remote/auth) and the skill honors the var (emit output, skip the
# irreversible action). run-skill.sh REFUSES this skill without DEVFLOW_EVAL=1 (footgun guard).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEVFLOW_EVAL=1
exec bash "${here}/../../eval/lib/run-skill.sh" "$@"
