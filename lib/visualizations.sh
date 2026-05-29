#!/usr/bin/env bash
# devflow/lib/visualizations.sh — visualization management
# Commands: config, list, open, update, render

VIZ_GLOBAL_CONFIG="${HOME}/.config/devflow/visualizations.json"
VIZ_PROJECT_CONFIG=".devflow/visualizations.json"

devflow_visualizations() {
  local action="${1:-list}"
  shift || true

  case "$action" in
    config) viz_config "$@" ;;
    list)   viz_list "$@" ;;
    open)   viz_open "$@" ;;
    update) viz_update "$@" ;;
    path)   viz_path "$@" ;;
    render) viz_render "$@" ;;
    *)      die "Unknown visualizations action: $action. Use: config, list, open, update, path, render" ;;
  esac
}

# ── Render (.excalidraw → PNG/SVG, pure-node, no browser/MCP) ─────────────────

# viz_render <input.excalidraw> [output-basename] [--width N]
# Exports via the bundled lib/excalidraw-export.cjs (excalidraw-to-svg + resvg-js).
# Global npm deps resolve through NODE_PATH. Prints the PNG path on the final
# stdout line for callers (e.g. the render-diagram skill) to capture and Read.
viz_render() {
  local input="${1:-}"
  [[ -z "$input" ]] && die "Usage: devflow visualizations render <input.excalidraw> [output-basename] [--width N]"
  [[ -f "$input" ]] || die "Input not found: $input"
  command -v node >/dev/null 2>&1 || die "node not found (install Node.js via mise)."
  command -v npm  >/dev/null 2>&1 || die "npm not found."

  local root script global_modules
  root="$(devflow_root)"
  script="${root}/lib/excalidraw-export.cjs"
  [[ -f "$script" ]] || die "Export script missing: $script"
  global_modules="$(npm root -g 2>/dev/null)"

  NODE_PATH="$global_modules" EXCAL_NODE_MODULES="$global_modules" node "$script" "$@" \
    || die "Diagram export failed. Ensure canvas, excalidraw-to-svg and @resvg/resvg-js are installed globally."
}

# ── Resolve visualization path ───────────────────────────────────────────────

viz_resolve_path() {
  # 1. Project config
  local proj
  proj="$(project_root 2>/dev/null || echo "")"
  if [[ -n "$proj" && -f "${proj}/${VIZ_PROJECT_CONFIG}" ]]; then
    local path
    path=$(jq -r '.path // empty' "${proj}/${VIZ_PROJECT_CONFIG}" 2>/dev/null)
    if [[ -n "$path" ]]; then
      # Resolve relative paths against project root
      if [[ "$path" != /* ]]; then
        path="${proj}/${path}"
      fi
      echo "$path"
      return 0
    fi
  fi

  # 2. Global config
  if [[ -f "$VIZ_GLOBAL_CONFIG" ]]; then
    local path
    path=$(jq -r '.path // empty' "$VIZ_GLOBAL_CONFIG" 2>/dev/null)
    if [[ -n "$path" ]]; then
      echo "$path"
      return 0
    fi
  fi

  # 3. Common locations
  for candidate in "docs/visualizations" "visualizations" "docs/diagrams"; do
    if [[ -n "$proj" && -d "${proj}/${candidate}" ]]; then
      echo "${proj}/${candidate}"
      return 0
    fi
  done

  # 4. Devflow's own visualizations as fallback
  local root
  root="$(devflow_root)"
  if [[ -d "${root}/visualizations" ]]; then
    echo "${root}/visualizations"
    return 0
  fi

  return 1
}

# ── Config ───────────────────────────────────────────────────────────────────

viz_config() {
  local path="" style="" categories="" format="" global=false show=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)       path="$2"; shift 2 ;;
      --style)      style="$2"; shift 2 ;;
      --categories) categories="$2"; shift 2 ;;
      --format)     format="$2"; shift 2 ;;
      --global)     global=true; shift ;;
      --show)       show=true; shift ;;
      *)            die "Unknown option: $1. Usage: devflow visualizations config [--path <dir>] [--style <preset>] [--categories <list>] [--format <mermaid|excalidraw>] [--global] [--show]" ;;
    esac
  done

  if [[ "$show" == true ]]; then
    _viz_show_config
    return 0
  fi

  # Interactive mode if no flags
  if [[ -z "$path" && -z "$style" && -z "$categories" && -z "$format" ]]; then
    _viz_interactive_config "$global"
    return 0
  fi

  # Write config from flags
  _viz_write_config "$path" "$style" "$categories" "$global" "$format"
}

_viz_show_config() {
  section "Visualization Configuration"

  local proj
  proj="$(project_root 2>/dev/null || echo "")"

  if [[ -n "$proj" && -f "${proj}/${VIZ_PROJECT_CONFIG}" ]]; then
    info "Project config: ${proj}/${VIZ_PROJECT_CONFIG}"
    cat "${proj}/${VIZ_PROJECT_CONFIG}"
    echo ""
  else
    detail "No project config found"
  fi

  if [[ -f "$VIZ_GLOBAL_CONFIG" ]]; then
    info "Global config: ${VIZ_GLOBAL_CONFIG}"
    cat "$VIZ_GLOBAL_CONFIG"
    echo ""
  else
    detail "No global config found"
  fi

  local viz_path
  if viz_path="$(viz_resolve_path)"; then
    ok "Active path: ${viz_path}"
  else
    warn "No visualization path resolved"
  fi
}

_viz_interactive_config() {
  local global="${1:-false}"

  section "Visualization Setup"

  # Path
  local default_path="docs/visualizations"
  read -rp "Visualization path [${default_path}]: " path
  path="${path:-$default_path}"

  # Style
  echo ""
  info "Style presets:"
  echo "  1) devflow  — Full color palette, YAML frontmatter, init blocks (default)"
  echo "  2) minimal  — Simple black/white, no frontmatter"
  echo "  3) custom   — Provide your own classDef colors"
  read -rp "Style [1]: " style_choice
  case "${style_choice:-1}" in
    1) style="devflow" ;;
    2) style="minimal" ;;
    3) style="custom" ;;
    *) style="devflow" ;;
  esac

  # Categories
  local default_cats="architecture,workflows,integrations,decisions"
  read -rp "Categories [${default_cats}]: " categories
  categories="${categories:-$default_cats}"

  # Format
  echo ""
  info "Diagram format:"
  echo "  1) mermaid     — Inline Mermaid in .md files (default)"
  echo "  2) excalidraw  — Author .excalidraw, render to PNG via /devflow:render-diagram"
  read -rp "Format [1]: " format_choice
  case "${format_choice:-1}" in
    1) format="mermaid" ;;
    2) format="excalidraw" ;;
    *) format="mermaid" ;;
  esac

  _viz_write_config "$path" "$style" "$categories" "$global" "$format"
}

_viz_write_config() {
  local path="$1" style="${2:-devflow}" categories="${3:-architecture,workflows,integrations,decisions}" global="${4:-false}" format="${5:-mermaid}"
  # Backward-compat: empty/unset format defaults to mermaid (existing behavior).
  format="${format:-mermaid}"

  if ! has_cmd jq; then
    die "jq is required for visualization config. Install with: brew install jq"
  fi

  # Build categories JSON array
  local cats_json
  cats_json=$(echo "$categories" | tr ',' '\n' | jq -R . | jq -s .)

  local config_json
  config_json=$(jq -n \
    --arg path "$path" \
    --arg style "$style" \
    --arg format "$format" \
    --argjson categories "$cats_json" \
    '{
      path: $path,
      style: $style,
      format: $format,
      categories: $categories,
      init: {
        flowchart: {
          rankSpacing: 50,
          nodeSpacing: 30,
          diagramPadding: 15
        }
      },
      frontmatter: true,
      symlinks: []
    }')

  local config_file
  if [[ "$global" == true ]]; then
    config_file="$VIZ_GLOBAL_CONFIG"
    mkdir -p "$(dirname "$config_file")"
  else
    local proj
    proj="$(project_root)"
    config_file="${proj}/${VIZ_PROJECT_CONFIG}"
    mkdir -p "$(dirname "$config_file")"
  fi

  echo "$config_json" > "$config_file"
  ok "Config written to: ${config_file}"

  # Create folder structure
  local base_path="$path"
  if [[ "$base_path" != /* ]]; then
    local proj
    proj="$(project_root 2>/dev/null || echo ".")"
    base_path="${proj}/${base_path}"
  fi

  echo "$categories" | tr ',' '\n' | while read -r cat; do
    cat="$(echo "$cat" | xargs)"  # trim whitespace
    mkdir -p "${base_path}/${cat}"
    [[ ! -f "${base_path}/${cat}/.gitkeep" ]] && touch "${base_path}/${cat}/.gitkeep"
  done

  ok "Folder structure created at: ${base_path}"
}

# ── List ─────────────────────────────────────────────────────────────────────

viz_list() {
  local viz_path
  if ! viz_path="$(viz_resolve_path)"; then
    die "No visualization folder found. Run 'devflow visualizations config' to set one up."
  fi

  section "Visualizations in ${viz_path}"

  local count=0
  while IFS= read -r -d '' file; do
    local rel="${file#"${viz_path}/"}"
    local title
    title=$(head -20 "$file" | grep '^# ' | head -1 | sed 's/^# //')
    printf "  ${BOLD}%-45s${RESET} %s\n" "$rel" "${title:-<no title>}"
    count=$((count + 1))
  done < <(find "$viz_path" -name '*.md' -not -name 'README.md' -print0 | sort -z)

  echo ""
  info "Total: ${count} visualization(s)"

  if [[ "$count" -eq 0 ]]; then
    detail "Run '/devflow:update-visualizations' to create initial diagrams"
  fi
}

# ── Open ─────────────────────────────────────────────────────────────────────

viz_open() {
  local target="${1:-}"
  local viz_path
  if ! viz_path="$(viz_resolve_path)"; then
    die "No visualization folder found. Run 'devflow visualizations config' to set one up."
  fi

  if [[ -z "$target" ]]; then
    # Open the README
    target="${viz_path}/README.md"
  elif [[ ! -f "$target" ]]; then
    # Try to find it relative to viz_path
    if [[ -f "${viz_path}/${target}" ]]; then
      target="${viz_path}/${target}"
    elif [[ -f "${viz_path}/${target}.md" ]]; then
      target="${viz_path}/${target}.md"
    else
      die "Visualization not found: ${target}"
    fi
  fi

  if has_cmd code; then
    code "$target"
    ok "Opened in VS Code: ${target}"
  elif [[ "$OSTYPE" == darwin* ]]; then
    open "$target"
    ok "Opened: ${target}"
  else
    info "File: ${target}"
    detail "Install VS Code or open manually"
  fi
}

# ── Update (delegates to Claude Code skill) ──────────────────────────────────

viz_update() {
  local description="${*:-}"

  if has_cmd claude; then
    info "Delegating to Claude Code /devflow:update-visualizations..."
    local prompt="Run /devflow:update-visualizations"
    [[ -n "$description" ]] && prompt="${prompt} \"${description}\""
    echo "$prompt" | claude --print 2>/dev/null \
      || die "Claude Code invocation failed"
  else
    warn "Claude Code not available for automated update."
    info "Manually run '/devflow:update-visualizations' in a Claude Code session."
    local viz_path
    if viz_path="$(viz_resolve_path)"; then
      info "Visualization path: ${viz_path}"
    fi
  fi
}

# ── Path (print resolved path) ──────────────────────────────────────────────

viz_path() {
  local viz_path
  if viz_path="$(viz_resolve_path)"; then
    echo "$viz_path"
  else
    die "No visualization path found. Run 'devflow visualizations config' to set one up."
  fi
}
