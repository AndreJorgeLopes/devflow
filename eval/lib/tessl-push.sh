#!/usr/bin/env bash
# Push a tessl skill-review score into Langfuse as a devflow-eval trace, so
# `devflow trace-review` can show a skill's REVIEW-QUALITY trend week over week and flag
# a drop. Unlike promptfoo shape-asserts (which sit at pass-rate 1.0 and never move), the
# tessl review score genuinely varies with skill quality, so it is the signal that makes
# the score column answer "did this skill get worse".
#
# The trace is tagged `devflow-eval` + `skill:<name>` with metadata.{devflow_eval,
# skill_name}, exactly like langfuse-push.sh, so trace-review attributes the score by
# skill + timestamp and excludes the eval trace from production aggregation. The score is
# normalised to 0..1 (tessl reports 0..100) so it sits on trace-review's -0.05 score-down
# threshold: a 5-point tessl drop flags.
#
# Prereqs: LANGFUSE_HOST + LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY (Langfuse UI keys).
#
# Usage:
#   bash lib/tessl-push.sh <skill-name> <score-0-100> [version-label]
#   # e.g. after: tessl review run --workspace <ws> --json  ->  .review.reviewScore
#   score=$(tessl review run --workspace "$WS" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["review"]["reviewScore"])')
#   bash lib/tessl-push.sh create-skill "$score" head
set -euo pipefail

SKILL="${1:?usage: tessl-push.sh <skill-name> <score-0-100> [version-label]}"
SCORE="${2:?usage: tessl-push.sh <skill-name> <score-0-100> [version-label]}"
VERSION="${3:-head}"
: "${LANGFUSE_HOST:?set LANGFUSE_HOST}"
: "${LANGFUSE_PUBLIC_KEY:?set LANGFUSE_PUBLIC_KEY}"
: "${LANGFUSE_SECRET_KEY:?set LANGFUSE_SECRET_KEY}"

# Keys read from the environment inside python, NEVER passed as argv (ps-visible). The
# child inherits the required LANGFUSE_* env vars checked above.
python3 - "$SKILL" "$SCORE" "$VERSION" "$LANGFUSE_HOST" <<'PY'
import sys, os, json, base64, urllib.request, urllib.error, time

skill, score_raw, version, host = sys.argv[1:5]
pk, sk = os.environ["LANGFUSE_PUBLIC_KEY"], os.environ["LANGFUSE_SECRET_KEY"]
try:
    score = float(score_raw)
except ValueError:
    print(f"score must be numeric, got {score_raw!r}", file=sys.stderr); sys.exit(2)
# normalise 0..100 -> 0..1; pass-through if already 0..1
value = score / 100.0 if score > 1.0 else score
auth = base64.b64encode(f"{pk}:{sk}".encode()).decode()
now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
tid = f"tessl-{skill}-{version}-{int(time.time())}"
batch = [
    {"id": "tt", "type": "trace-create", "timestamp": now,
     "body": {"id": tid, "name": f"{skill}: tessl review", "timestamp": now,
              "tags": ["devflow-eval", f"skill:{skill}", f"version:{version}", "tessl"],
              "metadata": {"devflow_eval": True, "skill_name": skill, "tessl_score_100": score}}},
    {"id": "ts", "type": "score-create", "timestamp": now,
     "body": {"id": f"s-{tid}", "traceId": tid, "name": "tessl_review", "value": value}},
]
req = urllib.request.Request(
    f"{host}/api/public/ingestion",
    data=json.dumps({"batch": batch}).encode(),
    headers={"Content-Type": "application/json", "Authorization": f"Basic {auth}"},
    method="POST")
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        print(f"pushed tessl_review score {value:.3f} (skill={skill} version={version}) -> {resp.status}")
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code}: {e.read().decode()[:300]}", file=sys.stderr); sys.exit(1)
except urllib.error.URLError as e:
    print(f"Langfuse unreachable at {host}: {e.reason}", file=sys.stderr); sys.exit(1)
PY
