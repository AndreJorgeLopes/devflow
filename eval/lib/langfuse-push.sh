#!/usr/bin/env bash
# Push promptfoo eval results into a self-hosted Langfuse (v2-compatible) as
# traces + numeric pass/fail scores, so skill quality can be tracked per version
# over time in the Langfuse UI.
#
# Prereqs (keys created in the Langfuse web UI — cannot be automated):
#   LANGFUSE_HOST        e.g. http://localhost:3100
#   LANGFUSE_PUBLIC_KEY  pk-lf-...
#   LANGFUSE_SECRET_KEY  sk-lf-...
#
# Usage:
#   npx -y promptfoo@latest eval --output results.json
#   bash lib/langfuse-push.sh results.json [version-label]
set -euo pipefail

RESULTS="${1:?usage: langfuse-push.sh <promptfoo-results.json> [version-label]}"
VERSION="${2:-head}"
: "${LANGFUSE_HOST:?set LANGFUSE_HOST}"
: "${LANGFUSE_PUBLIC_KEY:?set LANGFUSE_PUBLIC_KEY}"
: "${LANGFUSE_SECRET_KEY:?set LANGFUSE_SECRET_KEY}"

python3 - "$RESULTS" "$VERSION" "$LANGFUSE_HOST" "$LANGFUSE_PUBLIC_KEY" "$LANGFUSE_SECRET_KEY" <<'PY'
import sys, json, base64, urllib.request, time

results_path, version, host, pk, sk = sys.argv[1:6]
data = json.load(open(results_path))
# promptfoo result shape: results.results[] with .testCase, .success, .response.output, .score
rows = (data.get("results") or {}).get("results") or data.get("results") or []
auth = base64.b64encode(f"{pk}:{sk}".encode()).decode()

batch = []
for i, r in enumerate(rows):
    desc = (r.get("testCase") or {}).get("description") or f"test-{i}"
    success = bool(r.get("success"))
    out = ((r.get("response") or {}).get("output")) or ""
    tid = f"pf-{version}-{int(time.time())}-{i}"
    batch.append({"id": f"e{i}t", "type": "trace-create", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                  "body": {"id": tid, "name": desc, "tags": [f"version:{version}", "promptfoo"],
                           "output": out[:5000]}})
    batch.append({"id": f"e{i}s", "type": "score-create", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                  "body": {"id": f"s-{tid}", "traceId": tid, "name": "assert_pass", "value": 1 if success else 0}})

req = urllib.request.Request(
    f"{host}/api/public/ingestion",
    data=json.dumps({"batch": batch}).encode(),
    headers={"Content-Type": "application/json", "Authorization": f"Basic {auth}"},
    method="POST")
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        print(f"pushed {len(rows)} traces+scores (version={version}) → {resp.status}")
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code}: {e.read().decode()[:300]}", file=sys.stderr); sys.exit(1)
PY
