---
id: BUGS-fix-hindsight-startup-timeout
title: "Fix Hindsight Startup Timeout by Pre-loading User Config"
priority: P0
category: bugs
status: open
depends_on:
  - BUGS-fix-docker-compose-warnings
estimated_effort: L
files_to_touch:
  - docker/docker-compose.yml
  - lib/services.sh
---

# Fix Hindsight Startup Timeout by Pre-loading User Config

## Context

When running `devflow up`, the health check loop in `lib/services.sh` (lines 22-35) waits up to 60 seconds (30 retries x 2 seconds) for Hindsight to become healthy. On first start or when the container has no pre-existing config, Hindsight goes through an internal setup/initialization flow before becoming responsive, often exceeding this timeout.

The user already has a valid Hindsight configuration on the host machine at `~/.hindsight/`:

```
~/.hindsight/
  active_profile    # contains: "main"
  profiles/
    main.env        # contains: HINDSIGHT_API_LLM_PROVIDER=claude-code
    main.log        # log file
    metadata.json   # profile metadata with port, timestamps
```

The Docker container currently persists data in a named volume `hindsight-data` mounted at `/home/hindsight/.pg0` (the internal database). However, it does NOT receive the user's profile configuration, so Hindsight must re-initialize on every fresh container start.

The current compose volume configuration:

```yaml
volumes:
  - hindsight-data:/home/hindsight/.pg0
```

## Problem Statement

Hindsight frequently times out during `devflow up` because:

1. The container starts without the user's pre-existing profile config
2. Hindsight must run its setup/initialization flow before becoming healthy
3. The 60-second timeout (30 retries x 2s) is insufficient for this initialization
4. Even when it does complete, the initialized config inside the container is not synced back to the host

## Desired Outcome

- If the user has an existing `~/.hindsight/` config, it should be mounted into the container so Hindsight skips setup and starts quickly
- If the user has NO existing config, Hindsight runs its normal setup, and the resulting config is copied back to `~/.hindsight/` for future fast starts
- Before overwriting any existing host config, a dated backup is created
- A `--no-config-replace` flag allows users to prevent config sync-back

## Implementation Guide

### Part A: Mount user config into the container

**File:** `docker/docker-compose.yml`

Add a bind mount for the user's Hindsight config directory. The Hindsight Docker image stores its profile data at `/data/profiles` (based on the Hindsight documentation and typical container layout).

**Important:** Before implementing, verify the correct internal config path by checking the Hindsight image:

```bash
# Inspect the image to find where config lives
docker run --rm ghcr.io/vectorize-io/hindsight:latest ls -la /data/ 2>/dev/null || \
docker run --rm ghcr.io/vectorize-io/hindsight:latest ls -la /home/hindsight/ 2>/dev/null || \
docker run --rm ghcr.io/vectorize-io/hindsight:latest find / -name "active_profile" 2>/dev/null
```

Once you've confirmed the path (assume `/data` for now), update the volumes:

```yaml
volumes:
  - hindsight-data:/home/hindsight/.pg0
  - ${HINDSIGHT_CONFIG_DIR:-~/.hindsight}:/data/hindsight-config:ro
```

Note the `:ro` (read-only) — the container reads the config but doesn't write back to the bind mount. Write-back is handled by Part B.

**File:** `lib/services.sh`, in `devflow_up()` function

Before starting Docker Compose, ensure the config directory exists:

```bash
  # 2. Prepare Hindsight config
  section "Preparing Hindsight config"
  local hindsight_host_config="${HINDSIGHT_CONFIG_DIR:-${HOME}/.hindsight}"

  if [[ -d "$hindsight_host_config" && -f "$hindsight_host_config/active_profile" ]]; then
    ok "Found existing Hindsight config at $hindsight_host_config"
    export HINDSIGHT_CONFIG_DIR="$hindsight_host_config"
  else
    info "No existing Hindsight config found — Hindsight will run first-time setup"
    # Create the directory so the bind mount doesn't fail
    mkdir -p "$hindsight_host_config"
    export HINDSIGHT_CONFIG_DIR="$hindsight_host_config"
  fi
```

### Part B: Config backup and sync-back after startup

**File:** `lib/services.sh`, in `devflow_up()` function

After Hindsight becomes healthy (after the health check loop, around line 35), add config sync-back logic:

```bash
  # Sync Hindsight config back to host
  if [[ "${DEVFLOW_NO_CONFIG_REPLACE:-}" != "1" ]]; then
    _sync_hindsight_config "$compose_file" "$hindsight_host_config"
  else
    info "Config sync disabled (--no-config-replace)"
  fi
```

Add a new helper function (can be in `services.sh` or a separate function at the top):

```bash
_sync_hindsight_config() {
  local compose_file="$1"
  local host_config_dir="$2"
  local container_name="devflow-hindsight"
  # Adjust this path after verifying in Part A
  local container_config_path="/data"

  # Check if there's config in the container to copy back
  if ! docker exec "$container_name" test -f "${container_config_path}/active_profile" 2>/dev/null; then
    detail "No config to sync from container"
    return 0
  fi

  # Backup existing host config before overwriting
  if [[ -f "${host_config_dir}/profiles/main.env" ]]; then
    local backup_date
    backup_date="$(date +%Y-%m-%d)"
    local backup_file="${host_config_dir}/profiles/main.env.bak.${backup_date}"
    if [[ ! -f "$backup_file" ]]; then
      cp "${host_config_dir}/profiles/main.env" "$backup_file"
      detail "Backed up main.env to main.env.bak.${backup_date}"
    fi
  fi

  # Copy config from container to host
  docker cp "${container_name}:${container_config_path}/active_profile" "${host_config_dir}/active_profile" 2>/dev/null || true
  docker cp "${container_name}:${container_config_path}/profiles/" "${host_config_dir}/profiles/" 2>/dev/null || true

  detail "Synced Hindsight config to ${host_config_dir}"
}
```

### Part C: Support `--no-config-replace` flag

**File:** `lib/services.sh`, at the top of `devflow_up()` function

Parse the flag from arguments:

```bash
devflow_up() {
  # Parse flags
  local no_config_replace=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-config-replace) no_config_replace=1; shift ;;
      *) shift ;;
    esac
  done
  [[ "$no_config_replace" -eq 1 ]] && export DEVFLOW_NO_CONFIG_REPLACE=1

  # ... rest of function
```

### Part D: Increase health check tolerance

**File:** `lib/services.sh`, line 23

Increase the max retries to handle slow first-time setups:

```bash
  local retries=0 max_retries=60  # 120 seconds total (was 30 = 60s)
```

**File:** `docker/docker-compose.yml`, Hindsight healthcheck

Increase the start_period to give the container more time on first boot:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8888/health"]
  interval: 10s
  timeout: 10s
  retries: 10
  start_period: 60s
```

Changes: `interval: 30s -> 10s` (check more frequently), `retries: 3 -> 10`, `start_period: 15s -> 60s`.

## Acceptance Criteria

- [ ] When `~/.hindsight/` exists with valid config, `devflow up` starts Hindsight significantly faster (skips setup wizard)
- [ ] When `~/.hindsight/` does NOT exist, Hindsight runs first-time setup and copies config back to `~/.hindsight/`
- [ ] Before overwriting `~/.hindsight/profiles/main.env`, a backup is created as `main.env.bak.YYYY-MM-DD`
- [ ] `devflow up --no-config-replace` prevents syncing config back to host
- [ ] The health check timeout is long enough to survive first-time initialization (at least 120s)
- [ ] Existing named volume `hindsight-data` (database) is not affected
- [ ] `devflow down && devflow up` works correctly (config persists across restarts)

## Technical Notes

- **Container config path:** The exact path where Hindsight stores its config inside the container needs to be verified. Check the Hindsight Docker image entrypoint or documentation. Likely candidates: `/data`, `/home/hindsight/.hindsight`, `/root/.hindsight`. Run `docker run --rm ghcr.io/vectorize-io/hindsight:latest find / -name "active_profile" 2>/dev/null` to find it.
- **Bind mount vs volume:** We use a bind mount (not a named volume) for config because we need bidirectional host<->container access. The database stays on a named volume for Docker-managed persistence.
- **Read-only mount:** The `:ro` flag on the config bind mount prevents the container from modifying the host config directly. Sync-back is done explicitly via `docker cp` after startup. This prevents corruption if the container crashes mid-write.
- **Race condition:** There's a small window between "Hindsight is healthy" and "config is synced back" where a crash could lose new config. This is acceptable for a dev tool.
- **The `metadata.json` file:** Contains profile metadata including port numbers and timestamps. It should be synced along with `main.env` and `active_profile`.
- **The `.pg0` directory:** This is Hindsight's embedded PostgreSQL data directory. It's already on a named volume and should NOT be bind-mounted. Don't confuse config (profiles) with data (database).
- **Depends on BUGS-P0-002:** The compose file changes in this ticket build on the env var changes from BUGS-P0-002. Apply BUGS-P0-002 first.

## Verification

```bash
# 1. Fresh start with existing config — should be fast
devflow down
docker volume rm devflow_hindsight-data 2>/dev/null || true
time devflow up
# Expected: Hindsight healthy within ~30s (not timing out)

# 2. Verify config was mounted
docker exec devflow-hindsight cat /data/hindsight-config/active_profile 2>/dev/null
# Expected: "main" (or whatever the active profile is)

# 3. Verify backup was created
ls -la ~/.hindsight/profiles/main.env.bak.*
# Expected: main.env.bak.YYYY-MM-DD file exists

# 4. Test --no-config-replace
touch ~/.hindsight/profiles/main.env.marker
devflow down && devflow up --no-config-replace
cat ~/.hindsight/profiles/main.env.marker
# Expected: marker file still there (config wasn't overwritten)

# 5. Fresh start without any config
mv ~/.hindsight ~/.hindsight.bak
devflow down && docker volume rm devflow_hindsight-data 2>/dev/null || true
devflow up
ls ~/.hindsight/
# Expected: active_profile, profiles/ directory created after setup
mv ~/.hindsight.bak ~/.hindsight  # restore

# 6. Health check passes
curl -sf http://localhost:8888/health
# Expected: 200 OK
```
