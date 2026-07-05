#!/usr/bin/env bash
# Push promptfoo eval results into a self-hosted Langfuse as devflow-eval traces +
# numeric pass/fail scores, so a skill's quality can be tracked per version over time
# AND picked up by `devflow trace-review` (which keys eval scores by skill + timestamp).
#
# Each eval trace is tagged `devflow-eval` + `skill:<name>` and carries
# metadata.{devflow_eval, skill_name}. trace-review's _build_eval_scores uses exactly
# those markers to attribute the score to a skill and to hold the eval trace OUT of the
# production cost/latency aggregation. Without the skill name the score would land on an
# eval trace id that never joins to anything (the pre-2026 behaviour, cost/score = 0).
#
# Prereqs (keys created in the Langfuse web UI — cannot be automated):
#   LANGFUSE_HOST        e.g. http://localhost:3100
#   LANGFUSE_PUBLIC_KEY  pk-lf-...
#   LANGFUSE_SECRET_KEY  sk-lf-...
#
# Usage:
#   npx -y promptfoo@latest eval --output results.json
#   bash lib/langfuse-push.sh results.json <skill-name> [version-label]
#
# NOTE on meaningfulness: promptfoo pass-rate only *varies* for a skill whose config has
# a quality/LLM-judge assert. Shape-only asserts (is-json/contains) pass every run, so
# the score sits at 1.0 and never flags a regression. For a varying quality signal use
# tessl-push.sh (tessl review score) instead of / alongside this.
set -euo pipefail

RESULTS="${1:?usage: langfuse-push.sh <promptfoo-results.json> <skill-name> [version-label]}"
SKILL="${2:?usage: langfuse-push.sh <promptfoo-results.json> <skill-name> [version-label]}"
VERSION="${3:-head}"
: "${LANGFUSE_HOST:?set LANGFUSE_HOST}"
: "${LANGFUSE_PUBLIC_KEY:?set LANGFUSE_PUBLIC_KEY}"
: "${LANGFUSE_SECRET_KEY:?set LANGFUSE_SECRET_KEY}"

python3 - "$RESULTS" "$VERSION" "$SKILL" "$LANGFUSE_HOST" "$LANGFUSE_PUBLIC_KEY" "$LANGFUSE_SECRET_KEY" <<'PY'
import sys, json, base64, urllib.request, time

results_path, version, skill, host, pk, sk = sys.argv[1:7]
data = json.load(open(results_path))
# promptfoo result shape: results.results[] with .testCase, .success, .response.output, .score
rows = (data.get("results") or {}).get("results") or data.get("results") or []
auth = base64.b64encode(f"{pk}:{sk}".encode()).decode()
now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())

batch = []
for i, r in enumerate(rows):
    desc = (r.get("testCase") or {}).get("description") or f"test-{i}"
    success = bool(r.get("success"))
    out = ((r.get("response") or {}).get("output")) or ""
    tid = f"pf-{skill}-{version}-{int(time.time())}-{i}"
    batch.append({"id": f"e{i}t", "type": "trace-create", "timestamp": now,
                  "body": {"id": tid, "name": f"{skill}: {desc}", "timestamp": now,
                           "tags": ["devflow-eval", f"skill:{skill}", f"version:{version}", "promptfoo"],
                           "metadata": {"devflow_eval": True, "skill_name": skill},
                           "output": out[:5000]}})
    batch.append({"id": f"e{i}s", "type": "score-create", "timestamp": now,
                  "body": {"id": f"s-{tid}", "traceId": tid, "name": "assert_pass", "value": 1 if success else 0}})

req = urllib.request.Request(
    f"{host}/api/public/ingestion",
    data=json.dumps({"batch": batch}).encode(),
    headers={"Content-Type": "application/json", "Authorization": f"Basic {auth}"},
    method="POST")
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        print(f"pushed {len(rows)} eval traces+scores (skill={skill} version={version}) -> {resp.status}")
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code}: {e.read().decode()[:300]}", file=sys.stderr); sys.exit(1)
PY
