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
    *)       die "Unknown skills action: $action. Use: list, install, remove" ;;
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
