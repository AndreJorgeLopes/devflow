#!/usr/bin/env bash
# devflow/lib/skills.sh — devflow skills implementation
# Manages skills: list, install, remove.

SKILLS_TARGET_DIR=".claude/commands"

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

    # Check if installed in current project
    local proj
    proj="$(project_root 2>/dev/null || echo "")"
    if [[ -n "$proj" && -d "${proj}/${SKILLS_TARGET_DIR}/${name}" ]]; then
      printf "  %-25s %s\n" "" "(installed)"
    fi
  done

  echo ""
}

skills_install() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: devflow skills install <name>"

  local root
  root="$(devflow_root)"
  local registry
  registry="$(skills_registry)"
  local proj
  proj="$(project_root)"

  if ! has_cmd jq; then
    die "jq is required for skills management. Install with: brew install jq"
  fi

  # Look up skill in registry
  local skill_category
  skill_category=$(jq -r --arg n "$name" '.skills[] | select(.name == $n) | .category // empty' "$registry")

  if [[ -z "$skill_category" ]]; then
    die "Skill not found in registry: $name"
  fi

  local skill_dir="${root}/skills/${skill_category}"

  if [[ ! -d "$skill_dir" ]]; then
    die "Skill directory not found: $skill_dir"
  fi

  # Copy to project
  local target="${proj}/${SKILLS_TARGET_DIR}/${name}"
  mkdir -p "$(dirname "$target")"
  cp -r "$skill_dir" "$target"

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

  section "Converting devflow skills to Claude Code plugin"
  info "Output: ${output}"
  info "Plugin name: ${plugin_name}"

  # ── Create directory structure ────────────────────────────────────────────
  rm -rf "$output"
  mkdir -p "${output}/.claude-plugin"
  mkdir -p "${output}/commands"
  mkdir -p "${output}/skills/recall-before-task"
  mkdir -p "${output}/hooks"

  # ── Classification mapping ────────────────────────────────────────────────
  # recall-before-task → SKILL (auto-invoke before tasks)
  # All others → COMMANDS (user-triggered with $ARGUMENTS)

  local skill_count=0
  local command_count=0

  # Process each skill from the registry
  local count
  count=$(jq '.skills | length' "$registry")

  for (( i=0; i<count; i++ )); do
    local name category
    name=$(jq -r ".skills[$i].name" "$registry")
    category=$(jq -r ".skills[$i].category" "$registry")
    local file_rel
    file_rel=$(jq -r ".skills[$i].files[0]" "$registry")
    local source_file="${root}/skills/${file_rel}"

    if [[ ! -f "$source_file" ]]; then
      warn "Skill file not found, skipping: ${source_file}"
      continue
    fi

    if [[ "$name" == "memory-recall" ]]; then
      # memory-recall maps to the recall-before-task file → SKILL
      _convert_as_skill "$source_file" "${output}/skills/recall-before-task/SKILL.md" "recall-before-task"
      skill_count=$((skill_count + 1))
      ok "Skill: recall-before-task (auto-invoke)"
    else
      # Everything else → COMMAND
      cp "$source_file" "${output}/commands/${name}.md"
      command_count=$((command_count + 1))
      ok "Command: ${name}"
    fi
  done

  # ── Generate plugin.json ──────────────────────────────────────────────────
  cat > "${output}/.claude-plugin/plugin.json" <<PLUGIN_EOF
{
  "name": "${plugin_name}",
  "description": "Devflow AI development workflow skills — memory, worktrees, code review, process discipline, observability",
  "version": "0.1.0",
  "author": { "name": "Andre Jorge Lopes" },
  "repository": "https://github.com/andrejorgelopes/devflow",
  "license": "MIT",
  "commands": "./commands/",
  "skills": ["./skills/recall-before-task/SKILL.md"]
}
PLUGIN_EOF
  ok "Generated .claude-plugin/plugin.json"

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
  info "Skills:     ${skill_count}"
  info "Commands:   ${command_count}"
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

# Helper: convert a skill markdown file into a SKILL.md with name in frontmatter
_convert_as_skill() {
  local source="$1" dest="$2" skill_name="$3"

  # Read the source file and inject the name field into frontmatter
  if head -1 "$source" | grep -q '^---$'; then
    # File has frontmatter — inject name after the opening ---
    {
      echo "---"
      echo "name: ${skill_name}"
      # Copy everything between the first --- and the closing ---, excluding the opening ---
      sed -n '2,/^---$/p' "$source"
      # Copy everything after the closing frontmatter
      sed -n '/^---$/,$ p' "$source" | tail -n +2 | sed -n '/^---$/,$ p' | tail -n +2
    } > "$dest"
  else
    # No frontmatter — create one
    {
      echo "---"
      echo "name: ${skill_name}"
      echo "---"
      echo ""
      cat "$source"
    } > "$dest"
  fi
}
