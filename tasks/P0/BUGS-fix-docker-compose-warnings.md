---
id: BUGS-fix-docker-compose-warnings
title: "Fix Docker Compose Warnings (ANTHROPIC_API_KEY + version attribute)"
priority: P0
category: bugs
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - docker/docker-compose.yml
  - docker/.env.example
  - lib/services.sh
---

# Fix Docker Compose Warnings

## Context

When running `devflow up`, Docker Compose produces two warnings that clutter the output and confuse users:

```
WARN: The "ANTHROPIC_API_KEY" variable is not set. Defaulting to a blank string.
WARN: docker-compose.yml: the attribute 'version' is obsolete
```

The devflow Docker stack is defined in `docker/docker-compose.yml`. It runs Hindsight (memory MCP) and Langfuse (observability). The compose file currently:

1. Has `version: "3.9"` on line 1 (obsolete in Docker Compose v2)
2. Hardcodes `HINDSIGHT_API_LLM_API_KEY: ${ANTHROPIC_API_KEY}` on line 13, requiring the env var to be set even when the user uses `claude-code` as their LLM provider (which doesn't need an API key)

The user's actual Hindsight config at `~/.hindsight/profiles/main.env` shows:

```
HINDSIGHT_API_LLM_PROVIDER=claude-code
```

This means the user does NOT use an Anthropic API key — they use Claude Code's built-in subscription. The `ANTHROPIC_API_KEY` variable is irrelevant for this provider.

## Problem Statement

1. **Warning 1 (ANTHROPIC_API_KEY):** The compose file unconditionally references `${ANTHROPIC_API_KEY}` which produces a warning when unset. Since Hindsight supports multiple LLM providers (at least `anthropic`, `claude-code`, `openai`), the compose file should only pass provider-relevant env vars.

2. **Warning 2 (version attribute):** The `version: "3.9"` key is obsolete in Docker Compose v2+ (the current standard). It's ignored with a warning.

## Desired Outcome

- `devflow up` produces zero warnings from Docker Compose
- Users who use `claude-code` provider don't need to set `ANTHROPIC_API_KEY`
- Users who use `anthropic` provider can still pass their API key
- Users who use `openai` provider can pass their OpenAI key
- The `.env.example` file documents all supported configurations

## Implementation Guide

### Fix 1: Remove `version` attribute

**File:** `docker/docker-compose.yml`, line 1

Delete the line:

```yaml
version: "3.9"
```

The file should start directly with `services:`.

### Fix 2: Make LLM API key optional with a default

**File:** `docker/docker-compose.yml`, lines 12-13

Change the Hindsight environment block from:

```yaml
environment:
  HINDSIGHT_API_LLM_PROVIDER: ${HINDSIGHT_API_LLM_PROVIDER:-anthropic}
  HINDSIGHT_API_LLM_API_KEY: ${ANTHROPIC_API_KEY}
```

To:

```yaml
environment:
  HINDSIGHT_API_LLM_PROVIDER: ${HINDSIGHT_API_LLM_PROVIDER:-claude-code}
  HINDSIGHT_API_LLM_API_KEY: ${HINDSIGHT_API_LLM_API_KEY:-}
```

Key changes:

- **Default provider** changed from `anthropic` to `claude-code` (since that's the most common devflow user scenario — Claude Code subscription users)
- **API key** now uses a dedicated `HINDSIGHT_API_LLM_API_KEY` variable instead of hardcoding `ANTHROPIC_API_KEY`. The `:-` default-to-empty syntax prevents the "variable is not set" warning. An empty key is fine for the `claude-code` provider.

### Fix 3: Update `.env.example`

**File:** `docker/.env.example`

Replace the entire file with:

```
# ── Hindsight LLM Configuration ──────────────────────────────────────
# Provider options: claude-code, anthropic, openai
# Default: claude-code (uses Claude Code subscription, no API key needed)
HINDSIGHT_API_LLM_PROVIDER=claude-code

# Only needed if HINDSIGHT_API_LLM_PROVIDER=anthropic
# HINDSIGHT_API_LLM_API_KEY=sk-ant-xxx

# Only needed if HINDSIGHT_API_LLM_PROVIDER=openai
# HINDSIGHT_API_LLM_API_KEY=sk-xxx

# ── Langfuse API Keys (generated after first login at http://localhost:3100) ──
# LANGFUSE_SECRET_KEY=sk-lf-xxx
# LANGFUSE_PUBLIC_KEY=pk-lf-xxx
```

### Fix 4: Add provider validation to `devflow up` (optional but recommended)

**File:** `lib/services.sh`, in the `devflow_up()` function

After the Docker daemon check (line 14), before starting compose (line 17), add a validation step:

```bash
  # 2. Validate LLM provider config
  section "Checking LLM provider"
  local provider="${HINDSIGHT_API_LLM_PROVIDER:-claude-code}"
  case "$provider" in
    claude-code)
      ok "Using Claude Code subscription (no API key needed)"
      ;;
    anthropic)
      if [[ -z "${HINDSIGHT_API_LLM_API_KEY:-}" ]]; then
        warn "HINDSIGHT_API_LLM_PROVIDER=anthropic but HINDSIGHT_API_LLM_API_KEY is not set"
        info "Set it in your environment or in docker/.env"
      else
        ok "Anthropic API key configured"
      fi
      ;;
    openai)
      if [[ -z "${HINDSIGHT_API_LLM_API_KEY:-}" ]]; then
        warn "HINDSIGHT_API_LLM_PROVIDER=openai but HINDSIGHT_API_LLM_API_KEY is not set"
        info "Set it in your environment or in docker/.env"
      else
        ok "OpenAI API key configured"
      fi
      ;;
    *)
      warn "Unknown LLM provider: $provider (expected: claude-code, anthropic, openai)"
      ;;
  esac
```

This gives the user clear feedback about their configuration rather than a cryptic Docker Compose warning.

## Acceptance Criteria

- [ ] `devflow up` produces no warnings from Docker Compose about unset variables
- [ ] `devflow up` produces no warning about obsolete `version` attribute
- [ ] Users with `HINDSIGHT_API_LLM_PROVIDER=claude-code` (or unset) can run `devflow up` without setting any API key
- [ ] Users with `HINDSIGHT_API_LLM_PROVIDER=anthropic` who set `HINDSIGHT_API_LLM_API_KEY` still work correctly
- [ ] The `.env.example` file documents all supported provider configurations
- [ ] `devflow up` displays which LLM provider is being used

## Technical Notes

- **Docker Compose variable substitution:** `${VAR:-default}` provides a default and suppresses the "not set" warning. `${VAR}` without a default triggers the warning when unset. `${VAR-default}` (no colon) only uses default if var is truly unset (not if empty). Use `:-` for both unset and empty cases.
- **Hindsight `claude-code` provider:** This provider uses the Claude Code CLI's built-in authentication. It does not require an API key. It invokes `claude` CLI under the hood. Ensure Claude Code is installed and authenticated on the host for this to work.
- **Backward compatibility:** Users who have `ANTHROPIC_API_KEY` set in their environment won't automatically have it picked up anymore since the compose var changed to `HINDSIGHT_API_LLM_API_KEY`. Document this migration in the PR/changelog. Alternatively, you could add a fallback: `HINDSIGHT_API_LLM_API_KEY: ${HINDSIGHT_API_LLM_API_KEY:-${ANTHROPIC_API_KEY:-}}` — but this adds complexity. Prefer the clean break since devflow is pre-1.0.
- **The `docker/.env` file:** Docker Compose automatically loads `docker/.env` if it exists. Users can create `docker/.env` from `.env.example`. The env vars set in this file will be used for variable substitution in the compose file.

## Verification

```bash
# 1. Run devflow up and confirm no Docker Compose warnings
devflow up 2>&1 | grep -i "WARN"
# Expected: no output (no warnings)

# 2. Verify Hindsight starts with claude-code provider (default)
docker exec devflow-hindsight printenv HINDSIGHT_API_LLM_PROVIDER
# Expected: claude-code

# 3. Verify API key is empty (fine for claude-code)
docker exec devflow-hindsight printenv HINDSIGHT_API_LLM_API_KEY
# Expected: empty string or not set

# 4. Test with explicit anthropic provider
HINDSIGHT_API_LLM_PROVIDER=anthropic HINDSIGHT_API_LLM_API_KEY=sk-test devflow up 2>&1 | grep -i "WARN"
# Expected: no warnings

# 5. Verify version warning is gone
docker compose -f docker/docker-compose.yml config 2>&1 | grep -i "obsolete"
# Expected: no output
```
