#!/usr/bin/env bash
# devflow/lib/skills.sh — devflow skills implementation
# Manages skills: list, install, remove, convert.
#
# Layout (since registry v2.0.0):
#   skills/<name>/SKILL.md  — folder-based skills, one per name
#   skills/registry.json    — metadata (category, layer, description) per skill
#
# `devflow skills install <name>` copies skills/<name>/ to <project>/.claude/skills/<name>/.
# `devflow skills convert` regenerates devflow-plugin/ with folder-based skills + flat command mirrors.

SKILLS_TARGET_DIR=".claude/skills"

devflow_skills() {
  local action="${1:-list}"
  shift || true

  case "$action" in
    list)    skills_list ;;
    install) skills_install "$@" ;;
    remove)  skills_remove "$@" ;;
    convert) skills_convert "$@" ;;
    *)       die "Unknown skills action: $action. Use: list, install, remove, convert" ;;
  esac
}

skills_registry() {
  local root
  root="$(devflow_root)"
  local registry="${root}/skills/registry.json"

  if [[ ! -f "$registry" ]]; then
    die "Skills registry not found: $registry"
  fi
  echo "$registry"
}

skills_list() {
  local registry
  registry="$(skills_registry)"

  section "Available skills"

  if ! has_cmd jq; then
    die "jq is required for skills management. Install with: brew install jq"
  fi

  local count
  count=$(jq '.skills | length' "$registry")

  if [[ "$count" -eq 0 ]]; then
    info "No skills registered."
    return 0
  fi

  jq -r '.skills[] | "\(.name)\t\(.description // "No description")\t\(.category // "")"' "$registry" | while IFS=$'\t' read -r name desc category; do
    printf "  ${BOLD}%-25s${RESET} %s\n" "$name" "$desc"

    # Mark as installed if folder-based skill exists in current project
    local proj
    proj="$(project_root 2>/dev/null || echo "")"
    if [[ -n "$proj" && -f "${proj}/${SKILLS_TARGET_DIR}/${name}/SKILL.md" ]]; then
      printf "  %-25s %s\n" "" "(installed)"
    fi
  done

  echo ""
}

skills_install() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: devflow skills install <name>"

  local root proj
  root="$(devflow_root)"
  proj="$(project_root)"

  if ! has_cmd jq; then
    die "jq is required for skills management. Install with: brew install jq"
  fi

  # Validate skill exists in registry
  local registry
  registry="$(skills_registry)"
  local registered
  registered=$(jq -r --arg n "$name" '.skills[] | select(.name == $n) | .name' "$registry")

  if [[ -z "$registered" ]]; then
    die "Skill not found in registry: $name"
  fi

  local source_dir="${root}/skills/${name}"
  if [[ ! -f "${source_dir}/SKILL.md" ]]; then
    die "Skill source missing: ${source_dir}/SKILL.md"
  fi

  local target="${proj}/${SKILLS_TARGET_DIR}/${name}"
  mkdir -p "$(dirname "$target")"

  if [[ -d "$target" ]]; then
    rm -rf "$target"
  fi
  cp -R "$source_dir" "$target"

  ok "Installed skill '${name}' to ${SKILLS_TARGET_DIR}/${name}"
}

skills_remove() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: devflow skills remove <name>"

  local proj
  proj="$(project_root)"
  local target="${proj}/${SKILLS_TARGET_DIR}/${name}"

  if [[ ! -d "$target" ]]; then
    die "Skill '${name}' is not installed in this project."
  fi

  rm -rf "$target"
  ok "Removed skill '${name}' from ${SKILLS_TARGET_DIR}/${name}"
}

# ── Convert: transform devflow skills into a Claude Code plugin ──────────────
#
# Each skill is emitted twice into the plugin:
#   - devflow-plugin/skills/<name>/SKILL.md   (folder-based, agent-invokable via Skill tool)
#   - devflow-plugin/commands/<name>.md       (flat slash-command mirror, `name:` field stripped)
# The plugin.json `skills` array lists every SKILL.md so all skills are loaded.

skills_convert() {
  local output="" plugin_name="devflow" marketplace=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)  output="$2"; shift 2 ;;
      --name)    plugin_name="$2"; shift 2 ;;
      --marketplace) marketplace=true; shift ;;
      *)         die "Unknown option: $1. Usage: devflow skills convert [--output <dir>] [--name <name>] [--marketplace]" ;;
    esac
  done

  local root
  root="$(devflow_root)"
  local registry
  registry="$(skills_registry)"

  [[ -z "$output" ]] && output="${root}/devflow-plugin"

  if ! has_cmd jq; then
    die "jq is required for skills conversion. Install with: brew install jq"
  fi

  # Preserve marketplace flag if marketplace.json already exists in the output —
  # avoids accidentally wiping it when the user runs `devflow skills convert`
  # without the flag.
  if [[ "$marketplace" != true ]] && [[ -f "${output}/.claude-plugin/marketplace.json" ]]; then
    marketplace=true
  fi

  section "Converting devflow skills to Claude Code plugin"
  info "Output: ${output}"
  info "Plugin name: ${plugin_name}"

  # ── Create directory structure ────────────────────────────────────────────
  rm -rf "$output"
  mkdir -p "${output}/.claude-plugin"
  mkdir -p "${output}/commands"
  mkdir -p "${output}/skills"
  mkdir -p "${output}/hooks"

  # ── Emit each skill as both folder-based skill + flat command mirror ──────
  local skill_count=0
  local count
  count=$(jq '.skills | length' "$registry")

  # Collect plugin.json skills array entries as a newline-delimited list,
  # then emit through jq for proper JSON formatting.
  local skill_paths=""

  for (( i=0; i<count; i++ )); do
    local name
    name=$(jq -r ".skills[$i].name" "$registry")
    local source_dir="${root}/skills/${name}"
    local source_md="${source_dir}/SKILL.md"

    if [[ ! -f "$source_md" ]]; then
      warn "Skill source missing, skipping: ${source_md}"
      continue
    fi

    # 1) Folder-based skill (full directory copy)
    cp -R "$source_dir" "${output}/skills/${name}"

    # 2) Flat command mirror (strip `name:` line from frontmatter)
    _strip_name_to_command "$source_md" "${output}/commands/${name}.md"

    skill_count=$((skill_count + 1))
    skill_paths+="./skills/${name}/SKILL.md"$'\n'
    ok "Skill: ${name}"
  done

  # ── Generate plugin.json with all SKILL.md paths ─────────────────────────
  local skills_array
  skills_array=$(printf '%s\n' "$skill_paths" \
    | sed '/^$/d' \
    | jq -R . \
    | jq -s .)

  jq -n \
    --arg name "$plugin_name" \
    --argjson skills "$skills_array" \
    '{
      name: $name,
      description: "Devflow AI development workflow skills — memory, worktrees, code review, process discipline, observability",
      version: "0.1.0",
      author: { name: "Andre Jorge Lopes" },
      repository: "https://github.com/andrejorgelopes/devflow",
      license: "MIT",
      commands: "./commands/",
      skills: $skills
    }' > "${output}/.claude-plugin/plugin.json"
  ok "Generated .claude-plugin/plugin.json (${skill_count} skills)"

  # ── Generate hooks.json ───────────────────────────────────────────────────
  cat > "${output}/hooks/hooks.json" <<'HOOKS_EOF'
{
  "hooks": [
    {
      "type": "Stop",
      "command": "echo 'Session ending. Consider running /devflow:update-visualizations to update architecture diagrams. Run /devflow:session-summary to log metrics.'"
    }
  ]
}
HOOKS_EOF
  ok "Generated hooks/hooks.json"

  # ── Generate .mcp.json ───────────────────────────────────────────────────
  cat > "${output}/.mcp.json" <<'MCP_EOF'
{
  "mcpServers": {
    "hindsight": {
      "type": "http",
      "url": "http://localhost:8888/mcp/"
    }
  }
}
MCP_EOF
  ok "Generated .mcp.json"

  # ── Generate marketplace.json (if --marketplace) ──────────────────────────
  if [[ "$marketplace" == true ]]; then
    cat > "${output}/.claude-plugin/marketplace.json" <<MARKET_EOF
{
  "name": "${plugin_name}-marketplace",
  "owner": { "name": "Andre Jorge Lopes" },
  "metadata": { "description": "Devflow AI dev environment skills", "version": "0.1.0" },
  "plugins": [
    {
      "name": "${plugin_name}",
      "description": "AI development workflow skills",
      "source": "./",
      "version": "0.1.0"
    }
  ]
}
MARKET_EOF
    ok "Generated .claude-plugin/marketplace.json"
  fi

  # ── Summary ───────────────────────────────────────────────────────────────
  section "Plugin generated"
  info "Skills:     ${skill_count}  (folder-based, devflow-plugin/skills/<name>/SKILL.md)"
  info "Commands:   ${skill_count}  (flat mirrors, devflow-plugin/commands/<name>.md)"
  info "Hooks:      1 (Stop → session-summary reminder)"
  info "MCP deps:   1 (hindsight)"
  [[ "$marketplace" == true ]] && info "Marketplace: yes"
  echo ""
  info "Output directory: ${output}"
  echo ""

  # ── Validate with Claude CLI if available ─────────────────────────────────
  if has_cmd claude; then
    info "Validating plugin with Claude CLI..."
    if claude plugin validate "$output" 2>&1; then
      ok "Plugin validation passed"
    else
      warn "Plugin validation failed or not supported by this Claude CLI version"
    fi
  else
    detail "Claude CLI not found — skipping plugin validation"
  fi
}

# Helper: copy a SKILL.md to a flat slash-command file, stripping the `name:`
# field from the frontmatter (slash commands only need `description:`).
_strip_name_to_command() {
  local source="$1" dest="$2"

  awk '
    BEGIN { in_fm = 0 }
    NR==1 && /^---$/ { in_fm = 1; print; next }
    in_fm && /^---$/ { in_fm = 0; print; next }
    in_fm && /^name:[[:space:]]/ { next }
    { print }
  ' "$source" > "$dest"
}
