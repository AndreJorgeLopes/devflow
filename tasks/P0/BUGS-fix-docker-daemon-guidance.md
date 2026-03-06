---
id: BUGS-fix-docker-daemon-guidance
title: "Fix Docker Daemon Startup Guidance (OS-specific)"
priority: P0
category: bugs
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - lib/utils.sh
---

# Fix Docker Daemon Startup Guidance (OS-specific)

## Context

The `ensure_docker()` function in `lib/utils.sh` (lines 48-75) is responsible for checking that the Docker CLI is installed and the Docker daemon is reachable. It was recently improved to detect available runtimes (colima, Docker Desktop, OrbStack) and suggest the appropriate start command.

Current implementation:

```bash
ensure_docker() {
  # 1. Check Docker CLI is installed
  if ! has_cmd docker; then
    die "Docker CLI not found. Install from https://docs.docker.com/get-docker/"
  fi

  # 2. Check daemon is reachable
  if timeout 5 docker info >/dev/null 2>&1; then
    return 0
  fi

  # 3. Daemon unreachable — detect available runtimes and suggest accordingly
  local runtimes=()
  has_cmd colima          && runtimes+=("colima start")
  [[ -d "/Applications/Docker.app" ]] && runtimes+=("open -a Docker")
  has_cmd orbctl          && runtimes+=("orbctl start")

  if [[ ${#runtimes[@]} -gt 0 ]]; then
    local suggestions
    suggestions=$(printf "'%s'" "${runtimes[0]}")
    for ((i=1; i<${#runtimes[@]}; i++)); do
      suggestions+=", or '${runtimes[$i]}'"
    done
    die "Docker daemon is not running. Start it with: ${suggestions}"
  else
    die "Docker daemon is not running and no runtime found. Install one of: colima (brew install colima) or Docker Desktop (https://docs.docker.com/get-docker/)"
  fi
}
```

## Problem Statement

The current implementation has several gaps:

1. **No OS detection:** The fallback message assumes macOS (suggests `brew install colima`). On Linux, the suggestions should be `sudo systemctl start docker` or package manager install commands.

2. **No Linux-specific runtime detection:** On Linux, Docker typically runs via systemd. The function should detect this and suggest `sudo systemctl start docker`.

3. **Missing installation guidance when NO runtime exists:** The "no runtime found" message gives a generic URL. It should provide OS-specific, copy-pasteable install commands.

4. **Generic error phrasing:** The message says "Docker daemon is not running" but should say "devflow up requires a Docker runtime" to make it clear this is a devflow requirement, not a generic Docker error.

5. **Docker CLI not installed case is too sparse:** When the Docker CLI itself is missing (`docker` command not found), the message just gives a URL. It should detect the OS and give specific install instructions.

## Desired Outcome

The `ensure_docker()` function should:

- Detect the operating system (macOS vs Linux)
- On macOS: detect colima, Docker Desktop, OrbStack; suggest starting the one that's installed; if none, suggest installing colima via brew
- On Linux: detect systemd-managed docker service; suggest starting it; if not installed, suggest package manager install
- Provide clear, copy-pasteable commands in all cases
- Use "devflow requires a Docker runtime" phrasing

## Implementation Guide

**File:** `lib/utils.sh`, replace the entire `ensure_docker()` function (lines 48-75) with:

```bash
# ensure_docker — check Docker CLI exists and daemon is reachable
ensure_docker() {
  local os
  os="$(uname -s)"

  # 1. Check Docker CLI is installed
  if ! has_cmd docker; then
    _suggest_docker_install "$os"
    exit 1
  fi

  # 2. Check daemon is reachable
  if timeout 5 docker info >/dev/null 2>&1; then
    return 0
  fi

  # 3. Daemon unreachable — give OS-specific guidance
  _suggest_docker_start "$os"
  exit 1
}

# _suggest_docker_install <os> — suggest how to install Docker
_suggest_docker_install() {
  local os="$1"
  err "devflow requires Docker but the 'docker' command was not found."
  echo ""
  case "$os" in
    Darwin)
      info "Install a Docker runtime on macOS:"
      echo ""
      echo "  Option 1 (recommended): Install colima + Docker CLI"
      echo "    brew install colima docker"
      echo "    colima start"
      echo ""
      echo "  Option 2: Install Docker Desktop"
      echo "    https://docs.docker.com/desktop/install/mac-install/"
      echo ""
      echo "  Option 3: Install OrbStack"
      echo "    brew install orbstack"
      ;;
    Linux)
      info "Install Docker on Linux:"
      echo ""
      # Detect package manager
      if has_cmd apt-get; then
        echo "  sudo apt-get update && sudo apt-get install -y docker.io docker-compose-plugin"
        echo "  sudo systemctl enable --now docker"
        echo "  sudo usermod -aG docker \$USER  # then log out and back in"
      elif has_cmd dnf; then
        echo "  sudo dnf install -y docker docker-compose-plugin"
        echo "  sudo systemctl enable --now docker"
        echo "  sudo usermod -aG docker \$USER  # then log out and back in"
      elif has_cmd pacman; then
        echo "  sudo pacman -S docker docker-compose"
        echo "  sudo systemctl enable --now docker"
        echo "  sudo usermod -aG docker \$USER  # then log out and back in"
      else
        echo "  Visit: https://docs.docker.com/engine/install/"
        echo "  After installing, run: sudo systemctl enable --now docker"
      fi
      ;;
    *)
      info "Install Docker: https://docs.docker.com/get-docker/"
      ;;
  esac
  echo ""
}

# _suggest_docker_start <os> — suggest how to start the Docker daemon
_suggest_docker_start() {
  local os="$1"
  err "devflow requires a running Docker runtime, but the daemon is not reachable."
  echo ""

  case "$os" in
    Darwin)
      # Detect which runtimes are available on macOS
      local found=false

      if has_cmd colima; then
        info "Start colima:"
        echo "    colima start"
        found=true
      fi

      if [[ -d "/Applications/Docker.app" ]]; then
        info "Start Docker Desktop:"
        echo "    open -a Docker"
        found=true
      fi

      if has_cmd orbctl; then
        info "Start OrbStack:"
        echo "    orbctl start"
        found=true
      fi

      if ! $found; then
        info "No Docker runtime found. Install one:"
        echo ""
        echo "  Recommended: brew install colima docker && colima start"
        echo "  Alternative: https://docs.docker.com/desktop/install/mac-install/"
      fi
      ;;
    Linux)
      # Check if Docker is managed by systemd
      if has_cmd systemctl; then
        if systemctl list-unit-files docker.service >/dev/null 2>&1; then
          info "Start Docker via systemd:"
          echo "    sudo systemctl start docker"
          echo ""
          echo "  To start automatically on boot:"
          echo "    sudo systemctl enable docker"
        else
          info "Docker is installed but the systemd service is not found."
          echo "  Try: sudo dockerd &"
          echo "  Or reinstall: sudo apt-get install -y docker.io"
        fi
      else
        info "Start the Docker daemon:"
        echo "    sudo dockerd &"
      fi
      ;;
    *)
      info "Start the Docker daemon for your platform."
      info "See: https://docs.docker.com/config/daemon/start/"
      ;;
  esac
  echo ""
}
```

### Key design decisions:

1. **Extracted into helper functions** (`_suggest_docker_install`, `_suggest_docker_start`) for readability and testability. The underscore prefix indicates internal/private functions.

2. **Uses `uname -s`** for OS detection — this is portable and standard.

3. **On macOS:** Shows ALL available runtimes (not just the first one), so the user can choose. Each gets its own clearly labeled section.

4. **On Linux:** Detects the package manager (`apt-get`, `dnf`, `pacman`) to give distribution-specific install commands.

5. **Uses `exit 1` instead of `die`** because the multi-line output looks better without the `[devflow]` prefix on every line. The `err` call at the top provides the devflow branding.

6. **No interactive prompts:** The function only suggests commands — it never runs install commands automatically. This is a safety decision (we don't want `devflow up` to accidentally install Docker without user consent).

## Acceptance Criteria

- [ ] When Docker CLI is missing on macOS, the message suggests `brew install colima docker` as recommended, with Docker Desktop and OrbStack as alternatives
- [ ] When Docker CLI is missing on Linux, the message suggests the correct package manager command (`apt-get`, `dnf`, or `pacman`)
- [ ] When Docker daemon is not running on macOS with colima installed, the message suggests `colima start`
- [ ] When Docker daemon is not running on macOS with Docker Desktop installed, the message suggests `open -a Docker`
- [ ] When Docker daemon is not running on macOS with OrbStack installed, the message suggests `orbctl start`
- [ ] When Docker daemon is not running on macOS with NO runtime installed, the message suggests installing colima
- [ ] When Docker daemon is not running on Linux, the message suggests `sudo systemctl start docker`
- [ ] All error messages use "devflow requires" phrasing (not "Docker daemon is not running")
- [ ] Error messages are multi-line with copy-pasteable commands (not single-line walls of text)
- [ ] The function still exits non-zero in all failure cases (doesn't silently continue)

## Technical Notes

- **`timeout` command portability:** The current code uses `timeout 5 docker info`. On macOS, `timeout` is available via coreutils (`brew install coreutils`). If it's not available, the function should fall back. However, since this is pre-existing code and is out of scope for this ticket, leave it as-is. If it becomes an issue, file a separate ticket.
- **`systemctl list-unit-files`:** This command works even when the service is not running. It checks if the unit file exists, which tells us Docker is installed but stopped.
- **User group on Linux:** The `sudo usermod -aG docker $USER` suggestion requires a logout/login to take effect. The message should mention this.
- **No auto-install:** Never automatically install Docker. Only suggest commands. Users should make that choice explicitly.
- **OrbStack detection:** OrbStack provides the `orbctl` command. It can also provide a `docker` CLI shim, so `has_cmd docker` may return true even if OrbStack is the actual runtime.
- **Testing on Linux:** If you're developing on macOS, you can test the Linux code paths by overriding `uname` in tests or by running in a Linux container/VM. The macOS code paths can be tested directly.

## Verification

```bash
# 1. Test with Docker running (should pass silently)
ensure_docker
echo $?
# Expected: 0

# 2. Test macOS with Docker stopped (manual — stop Docker first)
# Stop colima/Docker Desktop/OrbStack, then:
devflow up 2>&1
# Expected: Multi-line message suggesting how to start the available runtime

# 3. Verify error phrasing
devflow up 2>&1 | head -3
# Expected: contains "devflow requires" not "Docker daemon is not running"

# 4. Verify the function still exits non-zero
bash -c 'source lib/utils.sh; ensure_docker; echo "should not reach here"' 2>&1
# Expected: error message, should NOT print "should not reach here"

# 5. Verify no regressions — devflow up with Docker running
devflow up
# Expected: normal startup, no errors from ensure_docker
```
