#!/usr/bin/env bash
# Seed custom Langfuse model-price definitions for Claude Code model IDs that
# Langfuse's built-in list doesn't match — notably the 1M-context variant
# `claude-opus-4-8[1m]` (the built-in `claude-opus-4-8` regex ends at `$`, so the
# `[1m]` suffix fails to match → cost shows 0 despite tokens).
#
# Idempotent: skips a model if its matchPattern already resolves a price.
# Run after the stack is up:  bash docker/langfuse-seed-models.sh
# Needs LANGFUSE_HOST + LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY (see ~/.config/zsh/secrets).
#
# NOTE: Langfuse computes cost at INGESTION time — seeding a model only affects
# traces ingested AFTER it exists; it does not retroactively re-cost old traces.
set -euo pipefail
HOST="${LANGFUSE_HOST:-http://localhost:3100}"
: "${LANGFUSE_PUBLIC_KEY:?set LANGFUSE_PUBLIC_KEY}"
: "${LANGFUSE_SECRET_KEY:?set LANGFUSE_SECRET_KEY}"
AUTH="${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}"

create_model() {
  local name="$1" pattern="$2" body="$3"
  if curl -s -u "$AUTH" "$HOST/api/public/models?limit=500" 2>/dev/null | grep -q "$name"; then
    echo "skip: $name already exists"; return 0
  fi
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" -X POST "$HOST/api/public/models" \
    -H "Content-Type: application/json" --data-binary "$body" 2>/dev/null)
  if [ "$code" = "400" ]; then echo "exists/rejected $name (http 400 — likely already present)"; else echo "create $name -> http=$code"; fi
}

# claude-opus-4-8[1m] — published opus-4-8 rates ($5/$25 + cache). The 1M-context
# >200K premium tier is NOT separately modeled (Langfuse uses a flat per-model price).
create_model "claude-opus-4-8-1m" 'claude-opus-4-8\[1m\]' '{
  "modelName": "claude-opus-4-8-1m",
  "matchPattern": "(?i)^(anthropic/)?claude-opus-4-8\\[1m\\]$",
  "unit": "TOKENS",
  "pricingTiers": [{
    "name": "default", "isDefault": true, "priority": 0, "conditions": [],
    "prices": {
      "input": 0.000005, "output": 0.000025,
      "cache_read_input_tokens": 0.0000005, "cache_creation_input_tokens": 0.00000625
    }
  }]
}'
