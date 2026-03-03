#!/usr/bin/env bash
# devflow/lib/seed.sh — devflow seed implementation
# Seeds Hindsight memory from project files (CLAUDE.md, package.json, etc.)

devflow_seed() {
  local project_dir="${1:-$(pwd)}"
  project_dir="$(cd "$project_dir" && pwd)"

  section "Seeding Hindsight memory from ${project_dir}"

  if ! hindsight_available; then
    die "Hindsight API not reachable at ${HINDSIGHT_API}. Run 'devflow up' first."
  fi

  local project_name
  project_name="$(basename "$project_dir")"
  local seeded=0

  # ── Seed from CLAUDE.md ────────────────────────────────────────────────────
  if [[ -f "${project_dir}/CLAUDE.md" ]]; then
    info "Seeding from CLAUDE.md..."
    local claude_content
    claude_content=$(cat "${project_dir}/CLAUDE.md")
    seed_mental_model "$project_name" "project-architecture" \
      "Project architecture and conventions from CLAUDE.md" \
      "$claude_content"
    seeded=$((seeded + 1))
  else
    skip "CLAUDE.md not found"
  fi

  # ── Seed from package.json ─────────────────────────────────────────────────
  if [[ -f "${project_dir}/package.json" ]]; then
    info "Seeding from package.json..."
    local pkg_info
    pkg_info=$(extract_package_info "${project_dir}/package.json")
    seed_mental_model "$project_name" "project-dependencies" \
      "Project dependencies and scripts from package.json" \
      "$pkg_info"
    seeded=$((seeded + 1))
  else
    skip "package.json not found"
  fi

  # ── Seed from README.md ────────────────────────────────────────────────────
  if [[ -f "${project_dir}/README.md" ]]; then
    info "Seeding from README.md..."
    local readme_content
    readme_content=$(cat "${project_dir}/README.md")
    seed_mental_model "$project_name" "project-readme" \
      "Project overview and setup from README.md" \
      "$readme_content"
    seeded=$((seeded + 1))
  else
    skip "README.md not found"
  fi

  # ── Seed from tsconfig.json ────────────────────────────────────────────────
  if [[ -f "${project_dir}/tsconfig.json" ]]; then
    info "Seeding from tsconfig.json..."
    local ts_content
    ts_content=$(cat "${project_dir}/tsconfig.json")
    seed_mental_model "$project_name" "typescript-config" \
      "TypeScript configuration and path aliases" \
      "$ts_content"
    seeded=$((seeded + 1))
  else
    skip "tsconfig.json not found"
  fi

  # ── Seed directory structure ───────────────────────────────────────────────
  info "Seeding directory structure..."
  local dir_tree
  dir_tree=$(generate_dir_tree "$project_dir")
  seed_mental_model "$project_name" "directory-structure" \
    "Project directory structure (top-level)" \
    "$dir_tree"
  seeded=$((seeded + 1))

  # ── Seed directives ────────────────────────────────────────────────────────
  info "Creating directives..."
  seed_directive "$project_name" "always-check-claude-md" \
    "Always consult CLAUDE.md before making architectural decisions in ${project_name}."
  seed_directive "$project_name" "follow-conventions" \
    "Follow the naming conventions and patterns established in ${project_name}'s CLAUDE.md."

  # ── Summary ────────────────────────────────────────────────────────────────
  section "Seed complete"
  log "Seeded ${seeded} mental models and 2 directives for project '${project_name}'."
}

# ── Helpers ───────────────────────────────────────────────────────────────────

extract_package_info() {
  local pkg="$1"
  if has_cmd jq; then
    jq '{name, version, description, scripts: (.scripts | keys), dependencies: (.dependencies | keys), devDependencies: (.devDependencies | keys)}' "$pkg" 2>/dev/null
  else
    cat "$pkg"
  fi
}

generate_dir_tree() {
  local dir="$1"
  # Use find to get top 2 levels, exclude hidden dirs and node_modules
  find "$dir" -maxdepth 2 \
    -not -path '*/\.*' \
    -not -path '*/node_modules/*' \
    -not -name node_modules \
    -not -name '.git' \
    -print 2>/dev/null | \
    sed "s|^${dir}/||" | sort
}

# Escape JSON string content
json_escape() {
  local str="$1"
  # Escape backslashes, double quotes, newlines, tabs, carriage returns
  str="${str//\\/\\\\}"
  str="${str//\"/\\\"}"
  str="${str//$'\n'/\\n}"
  str="${str//$'\t'/\\t}"
  str="${str//$'\r'/\\r}"
  echo "$str"
}

seed_mental_model() {
  local project="$1" id="$2" description="$3" content="$4"
  local escaped_content
  escaped_content="$(json_escape "$content")"
  local escaped_desc
  escaped_desc="$(json_escape "$description")"

  local body
  body=$(cat <<-JSON
{
  "type": "mental_model",
  "namespace": "${project}",
  "id": "${id}",
  "description": "${escaped_desc}",
  "content": "${escaped_content}"
}
JSON
  )

  if hindsight_post "/v1/retain" "$body" >/dev/null; then
    ok "Mental model: ${id}"
  else
    fail "Failed to seed mental model: ${id}"
  fi
}

seed_directive() {
  local project="$1" id="$2" instruction="$3"
  local escaped_instruction
  escaped_instruction="$(json_escape "$instruction")"

  local body
  body=$(cat <<-JSON
{
  "type": "directive",
  "namespace": "${project}",
  "id": "${id}",
  "instruction": "${escaped_instruction}"
}
JSON
  )

  if hindsight_post "/v1/retain" "$body" >/dev/null; then
    ok "Directive: ${id}"
  else
    fail "Failed to seed directive: ${id}"
  fi
}
