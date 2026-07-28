#!/usr/bin/env bash
# devflow/lib/init.sh — devflow init implementation
# Initialize devflow for the current user, optionally scoped to a project.

# _inject_devflow_block <target-file> <template-file>
# Idempotently inject/refresh the devflow-managed block. The template carries its own
# <!-- devflow --> / <!-- /devflow --> markers. If the target already has the block, replace
# its contents with the template (so existing installs pick up template updates on re-init);
# otherwise append. Creates the target from the template if absent. awk-based, bash-3.2-safe.
_inject_devflow_block() {
  local target="$1" tmpl="$2"
  [[ -f "$target" ]] || { cp "$tmpl" "$target"; return 0; }
  if grep -q '<!-- devflow -->' "$target" && grep -q '<!-- /devflow -->' "$target"; then
    awk -v tmpl="$tmpl" '
      /<!-- devflow -->/ { while ((getline line < tmpl) > 0) print line; close(tmpl); skip=1; next }
      /<!-- \/devflow -->/ { if (skip) { skip=0; next } }
      !skip { print }
    ' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"
  else
    printf '\n' >> "$target"
    cat "$tmpl" >> "$target"
  fi
}

# _register_settings <mode> <settings_file> <root> [is_dev]
# Idempotently register devflow config into ~/.claude/settings.json.
#   mode=marketplace : add extraKnownMarketplaces.devflow-marketplace (always writes)
#   mode=hooks       : add devflow hooks + telemetry env (writes only if something changed)
#
# Robust by construction — two guarantees that keep `devflow init` from ever corrupting or
# aborting on the user's settings.json under `set -euo pipefail`:
#   1. Atomic write: serialise to a temp file in the same directory, then os.replace() onto
#      settings.json. A crash/interrupt mid-write can never leave a truncated live file.
#   2. Malformed-input recovery: if the existing settings.json is not valid JSON, back it up
#      (timestamped) and rebuild from an empty config with a loud WARN, instead of raising a
#      traceback that would abort init at this section.
#
# Emits prefixed status lines (DEV:/USER:/Added/Skip/WARN:) for the caller's `case` to route.
_register_settings() {
  local mode="$1" settings_file="$2" root="$3" is_dev="${4:-false}"
  python3 -c "
import json, sys, os, shutil, tempfile, time

mode = sys.argv[1]
settings_path = sys.argv[2]
root = sys.argv[3]
is_dev = len(sys.argv) > 4 and sys.argv[4] == 'true'

def load_settings(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except (json.JSONDecodeError, ValueError):
        backup = path + '.corrupt-' + time.strftime('%Y%m%d%H%M%S') + '.bak'
        try:
            shutil.copy2(path, backup)
            print('WARN: existing settings.json is not valid JSON; backed it up to '
                  + backup + ' and rebuilt it from an empty config '
                  + '(your previous settings are preserved in the backup)')
        except OSError as e:
            print('WARN: existing settings.json is not valid JSON and could not be '
                  + 'backed up (' + str(e) + '); rebuilding from an empty config')
        return {}

def atomic_write(path, data):
    directory = os.path.dirname(path) or '.'
    fd, tmp = tempfile.mkstemp(dir=directory, prefix='.settings-', suffix='.tmp')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, indent=2)
            f.write('\n')
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

settings = load_settings(settings_path)

if mode == 'marketplace':
    extra = settings.setdefault('extraKnownMarketplaces', {})
    if is_dev:
        # Dev mode: local directory source — always prevails for contributors
        extra['devflow-marketplace'] = {
            'source': {'source': 'directory', 'path': root + '/devflow-plugin'},
            'autoUpdate': True
        }
        print('DEV: devflow-marketplace configured with local directory source')
    else:
        # End user: GitHub source with auto-update
        extra['devflow-marketplace'] = {
            'source': {'source': 'github', 'repo': 'AndreJorgeLopes/devflow'},
            'autoUpdate': True
        }
        print('USER: devflow-marketplace configured with GitHub source + auto-update')
    atomic_write(settings_path, settings)

elif mode == 'hooks':
    hook_root = root
    hooks = settings.setdefault('hooks', {})
    changed = False

    # Stop hook — finish-feature prompt
    stop_hooks = hooks.setdefault('Stop', [])
    stop_cmd = hook_root + '/lib/hooks/stop-finish-prompt.sh'
    if not any('stop-finish-prompt' in str(entry) for entry in stop_hooks):
        stop_hooks.append({'hooks': [{'type': 'command', 'command': stop_cmd}]})
        changed = True
        print('Added Stop hook: stop-finish-prompt')
    else:
        print('Skip: Stop hook already registered')

    # UserPromptSubmit hook — fetch-rebase
    ups_hooks = hooks.setdefault('UserPromptSubmit', [])
    ups_cmd = hook_root + '/lib/hooks/prompt-fetch-rebase.sh'
    if not any('prompt-fetch-rebase' in str(entry) for entry in ups_hooks):
        ups_hooks.append({'hooks': [{'type': 'command', 'command': ups_cmd}]})
        changed = True
        print('Added UserPromptSubmit hook: prompt-fetch-rebase')
    else:
        print('Skip: UserPromptSubmit hook already registered')

    # UserPromptSubmit hook — pending-reviews notification
    ups_pending_cmd = hook_root + '/lib/hooks/pending-reviews-notify.sh'
    if not any('pending-reviews-notify' in str(entry) for entry in ups_hooks):
        ups_hooks.append({'hooks': [{'type': 'command', 'command': ups_pending_cmd}]})
        changed = True
        print('Added UserPromptSubmit hook: pending-reviews-notify')
    else:
        print('Skip: pending-reviews-notify hook already registered')

    # PostToolUse hook — post-PR continuation prompt
    ptu_hooks = hooks.setdefault('PostToolUse', [])
    ptu_cmd = hook_root + '/lib/hooks/post-pr-continue.sh'
    if not any('post-pr-continue' in str(entry) for entry in ptu_hooks):
        ptu_hooks.append({'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': ptu_cmd}]})
        changed = True
        print('Added PostToolUse hook: post-pr-continue')
    else:
        print('Skip: PostToolUse hook already registered')

    # PreToolUse hook (matcher: Skill) — trace-review attribution enrichment.
    # Logs session_id+ts+skill to the sidecar so trace-review can attribute traces even
    # when Claude Code emits no skill_name span. Forward-only (no effect on past traces).
    pre_hooks = hooks.setdefault('PreToolUse', [])
    pre_cmd = hook_root + '/lib/hooks/skill-activation-log.sh'
    if not any('skill-activation-log' in str(entry) for entry in pre_hooks):
        pre_hooks.append({'matcher': 'Skill', 'hooks': [{'type': 'command', 'command': pre_cmd}]})
        changed = True
        print('Added PreToolUse hook: skill-activation-log')
    else:
        print('Skip: skill-activation-log hook already registered')

    # SessionStart hook — version-drift check. Warns (once/day, fail-silent) when the
    # installed devflow is behind the latest origin release, so a stale local install is
    # visible at session start instead of silently serving old skills/commands.
    ss_hooks = hooks.setdefault('SessionStart', [])
    ss_cmd = hook_root + '/lib/hooks/version-check.sh'
    if not any('version-check' in str(entry) for entry in ss_hooks):
        ss_hooks.append({'hooks': [{'type': 'command', 'command': ss_cmd}]})
        changed = True
        print('Added SessionStart hook: version-check')
    else:
        print('Skip: SessionStart hook already registered')

    # Claude Code OTel telemetry env — REQUIRED for trace-review to have ANY data.
    # Without these Claude Code emits no traces, so the whole trace-review feature is inert.
    # Points at the local devflow otel-collector (:4318); localhost-only, no external egress.
    # Set only if absent (never clobber a user's existing value).
    env = settings.setdefault('env', {})
    telemetry_defaults = {
        'CLAUDE_CODE_ENABLE_TELEMETRY': '1',
        'CLAUDE_CODE_ENHANCED_TELEMETRY_BETA': '1',
        'OTEL_TRACES_EXPORTER': 'otlp',
        'OTEL_EXPORTER_OTLP_PROTOCOL': 'http/protobuf',
        'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://localhost:4318',
        'OTEL_LOG_TOOL_DETAILS': '1',
    }
    # track which keys we actually inserted (never clobber an existing value)
    inserted = []
    for k, v in telemetry_defaults.items():
        if k not in env:
            env[k] = v
            inserted.append(k)
    if inserted:
        changed = True
        print('Added telemetry env: ' + ', '.join(inserted))
    else:
        print('Skip: telemetry env already set')

    if changed:
        atomic_write(settings_path, settings)

else:
    print('WARN: unknown settings mode: ' + mode)
    sys.exit(1)
" "$mode" "$settings_file" "$root" "$is_dev"
}

devflow_init() {
  # Parse flags out of the positional args. `--dev` (or env DEVFLOW_DEV=1) opts INTO local
  # dev mode (directory source + symlinks, no remote auto-update); the default is the GitHub
  # source with auto-update, even inside the devflow repo.
  local _devflow_dev_flag=false
  local _init_args=()
  local _a
  for _a in "$@"; do
    case "$_a" in
      --dev) _devflow_dev_flag=true ;;
      *) _init_args+=("$_a") ;;
    esac
  done
  local project_dir
  if [[ ${#_init_args[@]} -gt 0 ]]; then project_dir="${_init_args[0]}"; else project_dir="$(pwd)"; fi
  project_dir="$(cd "$project_dir" && pwd)"

  section "Initializing devflow"

  local root
  root="$(devflow_root)"
  local templates_dir="${root}/templates"
  local is_macos=false
  [[ "$(uname -s)" == "Darwin" ]] && is_macos=true

  # ── 1. Check prerequisites ─────────────────────────────────────────────────
  section "Checking prerequisites"

  local missing=0
  local docker_daemon_ok=true
  for cmd in docker git tmux; do
    if has_cmd "$cmd"; then
      ok "$cmd"
      # Enhanced Docker check: CLI exists, but is the daemon running?
      if [[ "$cmd" == "docker" ]]; then
        if ! timeout 5 docker info >/dev/null 2>&1; then
          docker_daemon_ok=false
          warn "Docker CLI found but daemon not running"
          local runtimes=()
          has_cmd colima && runtimes+=("colima start")
          [[ -d "/Applications/Docker.app" ]] && runtimes+=("open -a Docker")
          has_cmd orbctl && runtimes+=("orbctl start")
          if [[ ${#runtimes[@]} -gt 0 ]]; then
            local suggestions
            suggestions=$(printf "'%s'" "${runtimes[0]}")
            for ((i=1; i<${#runtimes[@]}; i++)); do
              suggestions+=", or '${runtimes[$i]}'"
            done
            info "  Start with: ${suggestions}"
          else
            info "  Install a runtime: colima (brew install colima) or Docker Desktop"
          fi
          warn "Layers requiring Docker (Hindsight, Langfuse) won't work until daemon is running"
        fi
      fi
    else
      status_fail "$cmd — not found"
      missing=1
    fi
  done

  if $is_macos; then
    if has_cmd brew; then
      ok "brew"
    else
      status_fail "brew — not found (required on macOS)"
      missing=1
    fi
  fi

  [[ $missing -eq 1 ]] && die "Install missing prerequisites before continuing."

  # ── 2. Check/install tools ─────────────────────────────────────────────────
  section "Checking devflow tools"

  _install_via_brew() {
    local name="$1"
    local formula="${2:-$1}"
    if $is_macos && has_cmd brew; then
      info "Installing ${name} via brew..."
      brew install "${formula}" 2>/dev/null && ok "${name} installed" || warn "Could not install ${name} via brew — install manually"
    else
      warn "${name} not found — install manually"
    fi
  }

  # Worktrunk
  if has_cmd wt; then
    ok "worktrunk (wt)"
  else
    _install_via_brew "worktrunk"
  fi

  # Code Review CLI — uses claude (primary) or opencode (fallback), no install needed
  if has_cmd claude; then
    ok "Code review CLI: claude"
  elif has_cmd opencode; then
    ok "Code review CLI: opencode (fallback)"
  else
    warn "No code review CLI found — install Claude Code or OpenCode"
  fi

  # uv (Python) — needed for Hindsight
  if has_cmd uv || has_cmd uvx; then
    ok "uv"
  else
    if $is_macos && has_cmd brew; then
      info "Installing uv via brew..."
      brew install uv 2>/dev/null && ok "uv installed" || warn "Could not install uv via brew — install manually (https://docs.astral.sh/uv/)"
    else
      warn "uv not found — install manually (https://docs.astral.sh/uv/)"
    fi
  fi

  # Hindsight — install profile via uvx with interactive provider selection
  if has_cmd uvx; then
    if [[ -f "${HOME}/.hindsight/profiles/main.env" ]]; then
      local current_provider
      current_provider="$(grep HINDSIGHT_API_LLM_PROVIDER "${HOME}/.hindsight/profiles/main.env" 2>/dev/null | cut -d= -f2)"
      ok "Hindsight profile 'main' exists (provider: ${current_provider:-unknown})"
    else
      section "Configuring Hindsight memory"
      log "Choose an LLM provider for Hindsight memory processing."
      log ""
      printf "  ${BOLD}1)${RESET} Claude Code      ${DIM}— uses your Claude Code subscription, no API key needed${RESET}\n"
      printf "  ${BOLD}2)${RESET} OpenAI Codex     ${DIM}— uses your OpenAI Codex subscription, no API key needed${RESET}\n"
      printf "  ${BOLD}3)${RESET} Anthropic API    ${DIM}— requires ANTHROPIC_API_KEY${RESET}\n"
      printf "  ${BOLD}4)${RESET} OpenAI API       ${DIM}— requires OPENAI_API_KEY${RESET}\n"
      printf "  ${BOLD}5)${RESET} Groq             ${DIM}— requires GROQ_API_KEY${RESET}\n"
      printf "  ${BOLD}6)${RESET} Ollama           ${DIM}— free, runs locally, no API key${RESET}\n"
      log ""
      printf "  Select provider [1]: "
      local provider_choice
      read -r provider_choice </dev/tty 2>/dev/null || provider_choice="1"
      provider_choice="${provider_choice:-1}"

      local hs_provider="" hs_needs_key=false
      case "$provider_choice" in
        1) hs_provider="claude-code" ;;
        2) hs_provider="openai-codex" ;;
        3) hs_provider="anthropic"; hs_needs_key=true ;;
        4) hs_provider="openai"; hs_needs_key=true ;;
        5) hs_provider="groq"; hs_needs_key=true ;;
        6) hs_provider="ollama" ;;
        *) hs_provider="claude-code"; warn "Invalid choice, defaulting to Claude Code" ;;
      esac

      local create_args=(main --port 8888 --env "HINDSIGHT_API_LLM_PROVIDER=${hs_provider}")

      if $hs_needs_key; then
        printf "  Enter API key: "
        local api_key
        read -rs api_key </dev/tty 2>/dev/null || api_key=""
        echo ""
        if [[ -n "$api_key" ]]; then
          create_args+=(--env "HINDSIGHT_API_LLM_API_KEY=${api_key}")
        else
          create_args+=(--env "HINDSIGHT_API_LLM_API_KEY=placeholder")
          warn "No API key provided. Set it later: uvx hindsight-embed profile set-env main HINDSIGHT_API_LLM_API_KEY <key>"
        fi
      fi

      uvx hindsight-embed profile create "${create_args[@]}" 2>/dev/null \
        && ok "Hindsight profile 'main' created (provider: ${hs_provider})" \
        || warn "Hindsight profile creation failed — configure manually: uvx hindsight-embed configure"
      uvx hindsight-embed profile set-active main 2>/dev/null
    fi
  else
    skip "uvx not available — skipping Hindsight profile setup"
  fi

  # ── 3. User-scoped config (CLAUDE.md, AGENTS.md) ──────────────────────────
  # These go in ~/.claude/ so they apply across ALL projects for this user.
  # They do NOT pollute the team's project-level CLAUDE.md.
  section "Setting up user-scoped agent config"

  local claude_home="${HOME}/.claude"
  mkdir -p "${claude_home}"

  # User-scoped CLAUDE.md — inject/refresh the devflow-managed block (idempotent).
  # Replaces the marker block on re-init so existing installs pick up template updates
  # (e.g. the diagram-complexity rule), instead of the old append-only-if-absent behavior.
  local claude_md_existed=false
  [[ -f "${claude_home}/CLAUDE.md" ]] && claude_md_existed=true
  _inject_devflow_block "${claude_home}/CLAUDE.md" "${templates_dir}/CLAUDE.md.tmpl"
  if $claude_md_existed; then
    ok "Refreshed devflow section in ~/.claude/CLAUDE.md"
  else
    ok "Created ~/.claude/CLAUDE.md"
  fi

  # User-scoped AGENTS.md — symlink to CLAUDE.md so they stay in sync
  if [[ -L "${claude_home}/AGENTS.md" ]]; then
    skip "~/.claude/AGENTS.md already symlinked"
  else
    rm -f "${claude_home}/AGENTS.md"
    ln -s CLAUDE.md "${claude_home}/AGENTS.md"
    ok "Symlinked ~/.claude/AGENTS.md -> CLAUDE.md"
  fi

  # ── 3b. Claude Code trust configuration ────────────────────────────────────
  section "Claude Code Trust Configuration"
  info "devflow creates worktrees in dynamic paths. To avoid trust dialogs"
  info "interrupting automated workflows, we can trust your home directory."
  info "This only skips the initial project trust prompt — file and tool"
  info "permissions are still enforced per-session."
  echo ""
  printf "${YELLOW}Trust ${HOME} for Claude Code? [Y/n] ${RESET}"
  read -r answer </dev/tty 2>/dev/null || answer="Y"
  if [[ "$answer" != "n" && "$answer" != "N" ]]; then
    if [[ -f "${HOME}/.claude.json" ]]; then
      python3 -c "
import json, os
config_path = os.path.expanduser('~/.claude.json')
with open(config_path, 'r+') as f:
    d = json.load(f)
    home = os.path.expanduser('~')
    projects = d.setdefault('projects', {})
    home_project = projects.setdefault(home, {})
    home_project['hasTrustDialogAccepted'] = True
    f.seek(0)
    json.dump(d, f, indent=2)
    f.truncate()
"
      ok "Home directory trusted for Claude Code"
    else
      warn "~/.claude.json not found — run Claude Code once first, then re-run devflow init"
    fi
  else
    skip "Skipped — you'll see trust dialogs for new worktrees"
  fi

  # ── 4. Project-scoped config (worktree, code review checks) ───────────────
  # These ARE per-project because they configure project-specific tooling.
  section "Setting up project files in ${project_dir}"

  # .worktrunk.toml — worktree config is inherently per-repo
  if [[ -f "${project_dir}/.worktrunk.toml" ]]; then
    skip ".worktrunk.toml already exists"
  else
    cp "${templates_dir}/.worktrunk.toml.tmpl" "${project_dir}/.worktrunk.toml"
    ok "Created .worktrunk.toml"
  fi

  # .devflow/checks/ — review rules are per-project (team can customize)
  if [[ -d "${templates_dir}/.devflow/checks" ]]; then
    mkdir -p "${project_dir}/.devflow/checks"
    local copied=0
    for check_file in "${templates_dir}/.devflow/checks/"*.md; do
      local basename
      basename="$(basename "$check_file")"
      if [[ ! -f "${project_dir}/.devflow/checks/${basename}" ]]; then
        cp "$check_file" "${project_dir}/.devflow/checks/${basename}"
        ((copied++))
      fi
    done
    if [[ $copied -gt 0 ]]; then
      ok "Copied ${copied} check file(s) to .devflow/checks/"
    else
      skip ".devflow/checks/ already up to date"
    fi
  fi

  # ── 5. Install Claude Code plugins ────────────────────────────────────────
  # Defined here (not in 5b) because the plugin-settings python block below references
  # it; a later `local` definition would leave this use unbound under `set -u`.
  local settings_file="${HOME}/.claude/settings.json"
  if has_cmd claude; then
    section "Installing Claude Code plugins"
    claude plugin marketplace add max-sixty/worktrunk 2>/dev/null
    claude plugin install worktrunk@worktrunk 2>/dev/null \
      && ok "worktrunk plugin installed" \
      || skip "worktrunk plugin already installed or not available"

    # Devflow plugin source. GitHub + auto-update is the DEFAULT so a merge to main reaches
    # every install (maintainers included). Local dev mode (directory source + symlinks, no
    # remote auto-update) is an EXPLICIT opt-in via `devflow init --dev` / `DEVFLOW_DEV=1`
    # (or `make plugin-dev`). It is NEVER auto-selected just because you are inside the repo —
    # that used to strand a maintainer on a stale local copy that never saw merged releases.
    local devflow_is_dev=false
    if [[ "$_devflow_dev_flag" == "true" ]] || [[ "${DEVFLOW_DEV:-}" == "1" ]]; then
      devflow_is_dev=true
    fi

    _register_settings marketplace "$settings_file" "$root" "$devflow_is_dev" 2>&1 | while IFS= read -r line; do
      case "$line" in
        DEV:*)  ok "${line#DEV: }" ;;
        USER:*) ok "${line#USER: }" ;;
        WARN:*) warn "${line#WARN: }" ;;
        *)      info "$line" ;;
      esac
    done

    if $devflow_is_dev; then
      # Dev mode: uninstall plugin to avoid duplicates with symlinks (step 6)
      claude plugin uninstall devflow@devflow-marketplace 2>/dev/null \
        && ok "devflow plugin uninstalled (dev mode uses symlinks instead)" \
        || skip "devflow plugin not installed (dev mode uses symlinks)"
    else
      # End user: install plugin from marketplace
      claude plugin install devflow@devflow-marketplace 2>/dev/null \
        && ok "devflow plugin installed" \
        || skip "devflow plugin already installed or up to date"
    fi
  else
    skip "Claude Code not installed — skipping plugin install"
  fi

  # ── 5b. Claude Code hooks ────────────────────────────────────────────────
  section "Registering Claude Code hooks"

  if [[ -f "$settings_file" ]]; then
    _register_settings hooks "$settings_file" "$root" 2>&1 | while IFS= read -r line; do
      case "$line" in
        Added*) ok "$line" ;;
        Skip*)  skip "$line" ;;
        WARN:*) warn "${line#WARN: }" ;;
        *)      info "$line" ;;
      esac
    done
  else
    warn "~/.claude/settings.json not found — run Claude Code once first, then re-run devflow init"
  fi

  # ── 5c. Seed Langfuse model prices (trace-review cost accuracy) ─────────────
  # Without seeded prices, Claude Code model IDs (incl. the [1m] 1M-context suffix and
  # newly-released models) resolve to no price and cost shows 0. Best-effort: needs the
  # Langfuse keys + a reachable stack; skips cleanly otherwise (seed later once up).
  section "Seeding Langfuse model prices"
  local seed_script="${root}/docker/langfuse-seed-models.sh"
  if [[ -f "$seed_script" ]]; then
    (
      # Contain the source: a user's secrets file may end in a non-zero-returning line
      # (e.g. `command -v <absent-tool>`); under the inherited `set -euo pipefail` that
      # would abort the whole subshell before any sentinel prints, silently killing
      # `devflow init` before step 6. set +e around the source (|| true on `source`
      # alone is NOT enough on bash 3.2 — set -e fires inside the sourced file first).
      set -a; set +e
      [[ -f "$HOME/.config/zsh/secrets" ]] && source "$HOME/.config/zsh/secrets" 2>/dev/null
      set -e; set +a
      : "${LANGFUSE_HOST:=http://localhost:3100}"
      if [[ -n "${LANGFUSE_PUBLIC_KEY:-}" && -n "${LANGFUSE_SECRET_KEY:-}" ]] \
         && curl -fsS -o /dev/null --connect-timeout 3 "${LANGFUSE_HOST}/api/public/health" 2>/dev/null; then
        bash "$seed_script" >/dev/null 2>&1 && echo "SEEDED" || echo "SEEDFAIL"
      else
        echo "SKIP"
      fi
    ) | while IFS= read -r r; do
      case "$r" in
        SEEDED) ok "Seeded model prices (opus-4-8[1m], sonnet-5, haiku-4-5, fable-5)" ;;
        SKIP)   skip "Langfuse unreachable or keys unset — run 'devflow up', then: bash docker/langfuse-seed-models.sh" ;;
        *)      warn "Model-price seeding failed — seed later: bash docker/langfuse-seed-models.sh" ;;
      esac
    done
  else
    skip "langfuse-seed-models.sh not found (skipping price seed)"
  fi

  # ── 6. Install devflow commands & skills ──────────────────────────────────
  # Dev mode: symlinks for instant iteration (no plugin cache copy delay)
  # End user mode: plugin handles discovery — symlinks would cause duplicates
  if has_cmd claude; then
    section "Installing devflow commands & skills"

    local commands_link="${HOME}/.claude/commands/devflow"
    local skills_link="${HOME}/.claude/skills/devflow-recall"

    if $devflow_is_dev; then
      local commands_target="${root}/devflow-plugin/commands"
      local skills_target="${root}/devflow-plugin/skills/recall-before-task"

      mkdir -p "${HOME}/.claude/commands" "${HOME}/.claude/skills"

      # Commands symlink
      if [[ -L "${commands_link}" ]]; then
        local current_target
        current_target="$(readlink "${commands_link}")"
        if [[ "${current_target}" == "${commands_target}" ]]; then
          ok "Devflow commands symlink healthy (${commands_link})"
        else
          warn "Commands symlink points to ${current_target}, expected ${commands_target}"
          ln -sfn "${commands_target}" "${commands_link}"
          ok "Commands symlink updated"
        fi
      elif [[ -d "${commands_link}" ]]; then
        warn "${commands_link} is a directory, not a symlink — skipping (manual cleanup needed)"
      else
        ln -sfn "${commands_target}" "${commands_link}"
        ok "Devflow commands installed (~/.claude/commands/devflow)"
      fi

      # Skills symlink
      if [[ -L "${skills_link}" ]]; then
        local current_skills_target
        current_skills_target="$(readlink "${skills_link}")"
        if [[ "${current_skills_target}" == "${skills_target}" ]]; then
          ok "Devflow skills symlink healthy (${skills_link})"
        else
          ln -sfn "${skills_target}" "${skills_link}"
          ok "Devflow skills symlink updated"
        fi
      elif [[ ! -e "${skills_link}" ]]; then
        ln -sfn "${skills_target}" "${skills_link}"
        ok "Devflow recall skill installed (~/.claude/skills/devflow-recall)"
      else
        skip "Devflow skill path exists but is not a symlink — skipping"
      fi
    else
      # End user mode: remove stale symlinks to avoid duplicates with the plugin
      if [[ -L "${commands_link}" ]]; then
        rm -f "${commands_link}"
        ok "Removed dev symlink (plugin handles commands now)"
      fi
      if [[ -L "${skills_link}" ]]; then
        rm -f "${skills_link}"
        ok "Removed dev symlink (plugin handles skills now)"
      fi
      skip "Devflow commands & skills provided by plugin (no symlinks needed)"
    fi
  else
    skip "Claude Code not installed — skipping devflow commands"
  fi

  # ── 6b. Install third-party skills ──────────────────────────────────────
  section "Installing third-party skills"

  # Hindsight skill for Claude Code
  if has_cmd claude; then
    local claude_skills_dir="${HOME}/.claude/skills/hindsight"
    mkdir -p "${claude_skills_dir}"
    if [[ -f "${root}/skills/recall-before-task/SKILL.md" ]]; then
      cp "${root}/skills/recall-before-task/SKILL.md" "${claude_skills_dir}/SKILL.md"
      ok "Hindsight skill installed for Claude Code (~/.claude/skills/hindsight/SKILL.md)"
    else
      warn "Hindsight skill template not found in devflow skills"
    fi
  fi

  # Skills for OpenCode
  if has_cmd opencode; then
    # Hindsight skill for OpenCode
    local oc_hs_skill_dir="${HOME}/.opencode/skills/hindsight"
    mkdir -p "${oc_hs_skill_dir}"
    if [[ -f "${root}/skills/recall-before-task/SKILL.md" ]]; then
      cp "${root}/skills/recall-before-task/SKILL.md" "${oc_hs_skill_dir}/SKILL.md"
      ok "Hindsight skill installed for OpenCode (~/.opencode/skills/hindsight/SKILL.md)"
    else
      warn "Hindsight skill template not found in devflow skills"
    fi
  fi

  # ── 7. Configure Hindsight MCP (user-scoped) ──────────────────────────────
  section "Configuring Hindsight MCP"

  local hindsight_url="${HINDSIGHT_API:-http://localhost:8888}"

  # Claude Code — MCP config is already user-scoped by default
  if has_cmd claude; then
    info "Adding Hindsight MCP to Claude Code..."
    claude mcp add \
      --transport http \
      -s user \
      hindsight \
      "${hindsight_url}/mcp/" 2>/dev/null \
      && ok "Hindsight MCP added to Claude Code" \
      || warn "Could not add MCP to Claude Code — add manually"
  else
    skip "Claude Code not installed — skipping MCP config"
  fi

  # OpenCode — user-scoped config at ~/.config/opencode/
  if has_cmd opencode; then
    info "Configuring Hindsight MCP for OpenCode..."
    local oc_config_dir="${HOME}/.config/opencode"
    mkdir -p "$oc_config_dir"

    local oc_config_file="${oc_config_dir}/opencode.json"
    if [[ -f "$oc_config_file" ]]; then
      if has_cmd jq; then
        # Fix trailing commas (common in hand-edited JSON) before merging
        local tmp sanitized
        tmp=$(mktemp)
        sanitized=$(mktemp)
        sed 's/,\([[:space:]]*[}]]\)/\1/g' "$oc_config_file" > "$sanitized"
        if jq '.mcpServers.hindsight = {"type": "sse", "url": "'"${hindsight_url}/mcp/sse"'"}' \
          "$sanitized" > "$tmp" 2>/dev/null; then
          mv "$tmp" "$oc_config_file"
          ok "Hindsight MCP added to OpenCode config"
        else
          warn "Could not merge OpenCode config — add Hindsight MCP manually"
        fi
        rm -f "$tmp" "$sanitized"
      else
        warn "jq not found — cannot merge OpenCode config. Add Hindsight MCP manually."
      fi
    else
      cat > "$oc_config_file" <<-OJSON
{
  "\$schema": "https://opencode.ai/config.json",
  "mcpServers": {
    "hindsight": {
      "type": "sse",
      "url": "${hindsight_url}/mcp/sse"
    }
  }
}
OJSON
      ok "Created OpenCode config with Hindsight MCP"
    fi
  else
    skip "OpenCode not installed — skipping MCP config"
  fi

  # ── 8. Worktrunk shell integration ────────────────────────────────────────
  if has_cmd wt; then
    section "Configuring Worktrunk shell integration"
    echo "y" | wt config shell install 2>/dev/null \
      && ok "Worktrunk shell integration installed" \
      || skip "Worktrunk shell integration already configured or not available"
  fi

  # ── 9. Summary ──────────────────────────────────────────────────────────────
  section "Init complete"
  log ""
  log "User-scoped (applies to all projects):"
  detail "~/.claude/CLAUDE.md    — Agent instructions with memory workflow"
  detail "~/.claude/AGENTS.md    — Multi-agent coordination"
  detail "MCP: Hindsight         — Persistent memory server"
  detail "Claude Code plugins    — worktrunk"
  detail "Devflow commands       — /devflow:new-feature, /devflow:create-pr, etc."
  detail "Skills                 — Hindsight, devflow-recall (Claude Code + OpenCode)"
  log ""
  log "Project-scoped (${project_dir}):"
  detail ".worktrunk.toml        — Git worktree config"
  detail ".devflow/checks/       — Code review check files"
  log ""
  log "Next steps:"
  detail "uvx hindsight-embed daemon start   — Start Hindsight memory daemon"
  detail "devflow up                         — Start Langfuse (Docker)"
  detail "devflow seed                       — Seed memory from project files"
  detail "devflow status                     — Check status of all layers"
  detail "devflow skills list                — Browse available skills"
  log ""
  log "Integrations:"
  info "  Chrome extension: Install from Chrome Web Store, enable with /chrome in Claude Code"
}
