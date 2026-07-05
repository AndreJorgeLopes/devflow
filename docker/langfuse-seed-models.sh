#!/usr/bin/env bash
# Seed custom Langfuse model-price definitions for Claude Code model IDs that
# Langfuse's built-in list doesn't match or doesn't price.
#
# Two gaps this fixes:
#   1. The 1M-context suffix. Claude Code emits `<model>[1m]` for 1M-context
#      requests. Langfuse's built-in price regexes end at `$` (e.g.
#      `^claude-opus-4-8$`), so the `[1m]` suffix never matches -> cost shows 0
#      despite real tokens. We add an explicit `[1m]`-anchored entry per model.
#   2. New model IDs. Langfuse's built-in list lags Anthropic releases, so
#      `claude-sonnet-5` and `claude-fable-5` resolve to no price (cost 0) until
#      seeded here.
#
# Idempotent: skips a model whose modelName already exists (exact match).
# Run after the stack is up:  bash docker/langfuse-seed-models.sh
# Needs LANGFUSE_HOST + LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY (see ~/.config/zsh/secrets).
#
# NOTE: Langfuse computes cost at INGESTION time — seeding a model only affects
# traces ingested AFTER it exists; it does not retroactively re-cost old traces.
#
# Rates are per-token USD (published Anthropic per-1M price / 1e6), current as of
# 2026-07. cache_read = 0.1x input, cache_write (5m) = 1.25x input. The >200K
# long-context premium tier is NOT separately modeled — Langfuse uses one flat
# per-model price, so the `[1m]` entries carry the same base rates as their
# standard sibling. Sonnet 5 is seeded at its STANDARD rate ($3/$15), not the
# intro rate ($2/$10 through 2026-08-31): for a cost-regression tool, seeding the
# lower intro rate now would make every sonnet-5 cost jump on 2026-09-01 and read
# as a false cost-up regression; the standard rate avoids that.
set -euo pipefail
HOST="${LANGFUSE_HOST:-http://localhost:3100}"
: "${LANGFUSE_PUBLIC_KEY:?set LANGFUSE_PUBLIC_KEY}"
: "${LANGFUSE_SECRET_KEY:?set LANGFUSE_SECRET_KEY}"
AUTH="${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}"

# Cache the existing model names once (exact-name idempotency check avoids the
# substring hazard where "claude-fable-5" greps as a prefix of
# "claude-fable-5-1m"). The list endpoint caps `limit` at 100, so paginate.
_EXISTING_NAMES="$(python3 - "$HOST" "$AUTH" <<'PY'
import sys, json, base64, urllib.request
host, auth = sys.argv[1], sys.argv[2]
hdr = {"Authorization": "Basic " + base64.b64encode(auth.encode()).decode()}
names, page = [], 1
while True:
    url = f"{host}/api/public/models?limit=100&page={page}"
    try:
        d = json.load(urllib.request.urlopen(urllib.request.Request(url, headers=hdr), timeout=10))
    except Exception:
        break  # unreadable -> emit what we have; POST 400 still guards duplicates
    data = d.get("data") or []
    names += [(m or {}).get("modelName") for m in data]
    meta = d.get("meta") or {}
    if page >= (meta.get("totalPages") or 1) or not data:
        break
    page += 1
print("\n".join(n for n in names if n))
PY
)"

_model_exists() { printf '%s\n' "$_EXISTING_NAMES" | grep -qxF "$1"; }

# seed <modelName> <matchPattern> <input/tok> <output/tok> <cache_read/tok> <cache_write/tok>
seed() {
  local name="$1" pattern="$2" pin="$3" pout="$4" pcr="$5" pcw="$6"
  if _model_exists "$name"; then
    echo "skip: $name already exists"; return 0
  fi
  local body
  body=$(printf '{
  "modelName": "%s",
  "matchPattern": "%s",
  "unit": "TOKENS",
  "pricingTiers": [{
    "name": "default", "isDefault": true, "priority": 0, "conditions": [],
    "prices": { "input": %s, "output": %s, "cache_read_input_tokens": %s, "cache_creation_input_tokens": %s }
  }]
}' "$name" "$pattern" "$pin" "$pout" "$pcr" "$pcw")
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" -X POST "$HOST/api/public/models" \
    -H "Content-Type: application/json" --data-binary "$body" 2>/dev/null)
  if [ "$code" = "400" ]; then echo "exists/rejected $name (http 400 — likely already present)"; else echo "create $name -> http=$code"; fi
}

# modelName | matchPattern (exact, case-insensitive, optional anthropic/ prefix) | in | out | cache_read | cache_write
# Opus 4.8   $5/$25    Sonnet 5  $3/$15    Haiku 4.5 $1/$5    Fable 5  $10/$50
seed "claude-opus-4-8-1m"  '(?i)^(anthropic/)?claude-opus-4-8\\[1m\\]$'  0.000005 0.000025 0.0000005 0.00000625
seed "claude-sonnet-5"     '(?i)^(anthropic/)?claude-sonnet-5$'          0.000003 0.000015 0.0000003 0.00000375
seed "claude-sonnet-5-1m"  '(?i)^(anthropic/)?claude-sonnet-5\\[1m\\]$'  0.000003 0.000015 0.0000003 0.00000375
seed "claude-haiku-4-5"    '(?i)^(anthropic/)?claude-haiku-4-5$'         0.000001 0.000005 0.0000001 0.00000125
seed "claude-fable-5"      '(?i)^(anthropic/)?claude-fable-5$'           0.00001  0.00005  0.000001  0.0000125
seed "claude-fable-5-1m"   '(?i)^(anthropic/)?claude-fable-5\\[1m\\]$'   0.00001  0.00005  0.000001  0.0000125
