#!/usr/bin/env bash
# scripts/build-skills.sh — generate the plugin skill copies from the ONE source of truth.
#
# Source of truth: repo-root skills/<name>/SKILL.md (+ bundle files). Everything else is
# GENERATED and must never be hand-edited:
#   - devflow-plugin/skills/<name>/     byte copy of skills/<name>/ minus dev-only files
#   - devflow-plugin/commands/<name>.md SKILL.md with the frontmatter rewritten to command form
# `make flows` then regenerates devflow-plugin/flows/** from devflow-plugin/{commands,skills}.
#
# Command frontmatter transform (all 28 skills are uniform: name + single-line description):
#   SKILL.md:  ---\nname: X\ndescription: Y\n---\n<body>
#   command:   ---\ndescription: [VERSION] Y\n---\n<body>   (VERSION from plugin.json)
#
# Dev-only files kept at repo root but NOT shipped in the plugin: eval bench fixtures.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/skills"
# Output goes to the real plugin tree by default; DEVFLOW_PLUGIN_OUT lets the guard render a
# throwaway copy to compare against (single source of the transform logic).
OUT="${DEVFLOW_PLUGIN_OUT:-${ROOT}/devflow-plugin}"
PLUGIN_SKILLS="${OUT}/skills"
PLUGIN_CMDS="${OUT}/commands"

command -v jq >/dev/null 2>&1 || { echo "build-skills: jq is required" >&2; exit 1; }
[[ -d "$SRC" ]] || { echo "build-skills: missing $SRC" >&2; exit 1; }

# VERSION always comes from the real plugin manifest, even when rendering to a temp OUT.
VERSION="$(jq -r .version "${ROOT}/devflow-plugin/.claude-plugin/plugin.json")"

# Files that live beside a skill at repo root for dev/CI but must NOT ship in the plugin.
_is_dev_only() {
  case "$(basename "$1")" in
    determinism.promptfooconfig.yaml) return 0 ;;
    *) return 1 ;;
  esac
}

mkdir -p "$PLUGIN_SKILLS" "$PLUGIN_CMDS"

# ── 1. Prune generated copies whose source skill no longer exists ──
for d in "$PLUGIN_SKILLS"/*/; do
  [[ -d "$d" ]] || continue
  n="$(basename "$d")"
  [[ -f "${SRC}/${n}/SKILL.md" ]] || { echo "prune skill: ${n}"; rm -rf "$d"; }
done
for c in "$PLUGIN_CMDS"/*.md; do
  [[ -f "$c" ]] || continue
  n="$(basename "$c" .md)"
  [[ -f "${SRC}/${n}/SKILL.md" ]] || { echo "prune command: ${n}"; rm -f "$c"; }
done

# ── 2. Generate each skill's plugin copy + command ──
for skdir in "$SRC"/*/; do
  [[ -d "$skdir" ]] || continue
  n="$(basename "$skdir")"
  src_skill="${skdir}SKILL.md"
  [[ -f "$src_skill" ]] || { echo "build-skills: ${n}/ has no SKILL.md — skipping" >&2; continue; }

  # Fail loud if the frontmatter carries keys beyond name/description: the command
  # transform (2b) only preserves the description, so any extra key (e.g. allowed-tools)
  # would be silently dropped. Force a conscious update of this generator instead.
  extra_keys="$(awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; if(n>=2)exit; next} n==1 && /^[a-zA-Z_-]+:/{k=$0; sub(/:.*/,"",k); if(k!="name"&&k!="description") print k}' "$src_skill")"
  [[ -z "$extra_keys" ]] || { echo "build-skills: ${n}/SKILL.md has unsupported frontmatter key(s): $(echo $extra_keys) — update scripts/build-skills.sh to carry them into the command form before adding them" >&2; exit 1; }

  # 2a. Plugin skill dir: fresh byte copy of the source minus dev-only files.
  out_skdir="${PLUGIN_SKILLS}/${n}"
  rm -rf "$out_skdir"
  mkdir -p "$out_skdir"
  # Copy the tree, then drop dev-only files. cp -R keeps requirements.json, references/,
  # AGENTS.md, TEMPLATES.md, *.example.yaml, spike-template.md — everything the plugin needs.
  cp -R "${skdir}." "$out_skdir/"
  while IFS= read -r f; do
    _is_dev_only "$f" && rm -f "$f"
  done < <(find "$out_skdir" -type f)

  # 2b. Command file: rewrite frontmatter to command form, keep the body verbatim.
  desc="$(awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1 && sub(/^description:[[:space:]]*/,""){print; exit}' "$src_skill")"
  [[ -n "$desc" ]] || { echo "build-skills: ${n}/SKILL.md has no description in frontmatter" >&2; exit 1; }

  out_cmd="${PLUGIN_CMDS}/${n}.md"
  {
    printf -- '---\n'
    printf 'description: [%s] %s\n' "$VERSION" "$desc"
    printf -- '---\n'
    # Body = everything after the closing --- of the frontmatter block, verbatim.
    awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; if(n==2){body=1; next}} body{print}' "$src_skill"
  } > "$out_cmd"

  echo "built skill: ${n}"
done

# ── 3. Regenerate the plugin.json "skills" array so a newly added/removed skill is
# actually loaded. Order follows skills/registry.json; any source dir not in the
# registry is appended alphabetically. All other plugin.json fields are preserved. ──
REAL_PJ="${ROOT}/devflow-plugin/.claude-plugin/plugin.json"
REGISTRY="${SRC}/registry.json"
skill_names="$(for d in "$SRC"/*/; do [[ -f "${d}SKILL.md" ]] && basename "$d"; done | sort)"
ordered=""
if [[ -f "$REGISTRY" ]]; then
  while IFS= read -r rn; do
    [[ -n "$rn" ]] || continue
    printf '%s\n' "$skill_names" | grep -qx "$rn" && ordered="${ordered}${rn}"$'\n'
  done < <(jq -r '.skills[].name' "$REGISTRY")
fi
# Append any source skills the registry did not list (keeps them loadable, flags the gap by order).
while IFS= read -r sn; do
  [[ -n "$sn" ]] || continue
  printf '%s\n' "$ordered" | grep -qx "$sn" || ordered="${ordered}${sn}"$'\n'
done <<< "$skill_names"

skills_array="$(printf '%s\n' "$ordered" | sed '/^$/d' | sed 's#^#./skills/#; s#$#/SKILL.md#' | jq -R . | jq -s .)"
out_pj="${OUT}/.claude-plugin/plugin.json"
mkdir -p "${OUT}/.claude-plugin"
jq --argjson skills "$skills_array" '.skills = $skills' "$REAL_PJ" > "${out_pj}.tmp" && mv "${out_pj}.tmp" "$out_pj"
echo "built plugin.json skills array ($(printf '%s\n' "$ordered" | sed '/^$/d' | wc -l | tr -d ' ') skills)"
