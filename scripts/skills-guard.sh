#!/usr/bin/env bash
# scripts/skills-guard.sh — pre-PR guard that RESCUES skill edits made in the wrong tree.
#
# The source of truth is repo-root skills/<name>/SKILL.md (+ bundle files). The plugin trees
# devflow-plugin/skills/ and devflow-plugin/commands/ are GENERATED. If someone edits a
# generated copy directly, a plain drift check would happily OVERWRITE their edit on the next
# `make skills-sync`, silently destroying the work. This guard instead detects that case and
# FOLDS the edit back into the source, then regenerates so every copy is consistent again.
#
# Detection is exact, not heuristic: render the source to a throwaway tree with build-skills,
# then any skill whose real plugin copy differs from that render is out of sync. Among those,
# the git delta since the base ref decides who is authoritative:
#   - source changed, copy did not      -> normal "run make skills-sync" (copy is just stale)
#   - copy changed, source did not       -> MISPLACED hand-edit -> fold back into source
#   - both changed                       -> ambiguous -> ask the human
#   - neither changed (pre-existing drift)-> recommend skills-sync (source wins), no auto-fold
#
# Modes:
#   (default)   detect + relocate + regenerate + report. Exit non-zero only if ambiguous.
#   --check     detect only; exit 1 if any misplaced edit exists (for CI / hooks). No writes.
#
# Base ref: BASE env, else merge-base with origin/main, else HEAD.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="relocate"
[[ "${1:-}" == "--check" ]] && MODE="check"

# ── Base ref for the feature delta (committed + staged + unstaged + untracked) ──
if [[ -n "${BASE:-}" ]]; then
  base="$BASE"
elif git rev-parse --verify -q origin/main >/dev/null 2>&1; then
  base="$(git merge-base origin/main HEAD 2>/dev/null || echo HEAD)"
else
  base="HEAD"
fi
changed="$(
  { git diff --name-only "$base" 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null; } | sort -u
)"
_changed_under() { printf '%s\n' "$changed" | grep -q "^$1" 2>/dev/null; }

# ── Render source -> throwaway tree, find skills whose real copy differs ──
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/skills" "$tmp/commands"
DEVFLOW_PLUGIN_OUT="$tmp" bash scripts/build-skills.sh >/dev/null

out_of_sync=""
for skdir in skills/*/; do
  n="$(basename "$skdir")"
  [[ -f "skills/${n}/SKILL.md" ]] || continue
  cmd_diff=1; skl_diff=1
  diff -q "devflow-plugin/commands/${n}.md" "$tmp/commands/${n}.md" >/dev/null 2>&1 && cmd_diff=0
  diff -rq "devflow-plugin/skills/${n}" "$tmp/skills/${n}" >/dev/null 2>&1 && skl_diff=0
  if [[ $cmd_diff -ne 0 || $skl_diff -ne 0 ]]; then
    out_of_sync="$out_of_sync $n"
  fi
done
out_of_sync="$(echo "$out_of_sync" | xargs 2>/dev/null || true)"

if [[ -z "$out_of_sync" ]]; then
  echo "skills-guard: OK — plugin copies are in sync with the source."
  exit 0
fi

# ── Classify each out-of-sync skill by the git delta ──
misplaced=""; stale=""; ambiguous=""; predrift=""
for n in $out_of_sync; do
  src_ch=false; gen_ch=false
  _changed_under "skills/${n}/" && src_ch=true
  { _changed_under "devflow-plugin/commands/${n}.md" || _changed_under "devflow-plugin/skills/${n}/"; } && gen_ch=true
  if   $gen_ch && ! $src_ch; then misplaced="$misplaced $n"
  elif $src_ch && ! $gen_ch; then stale="$stale $n"
  elif $src_ch && $gen_ch;   then ambiguous="$ambiguous $n"
  else predrift="$predrift $n"; fi
done

[[ -n "$stale" ]]    && echo "skills-guard: source changed, copies stale (run 'make skills-sync'):$stale"
[[ -n "$predrift" ]] && echo "skills-guard: pre-existing drift, source is authoritative (run 'make skills-sync'):$predrift"

if [[ -z "$misplaced" && -z "$ambiguous" ]]; then
  # Only benign staleness / pre-existing drift — not this guard's rescue job.
  [[ "$MODE" == "check" ]] && exit 0
  exit 0
fi

echo "skills-guard: edits made in the GENERATED trees (source of truth is skills/<name>/SKILL.md):"
for n in $misplaced; do
  s=""
  _changed_under "devflow-plugin/commands/${n}.md" && s="commands/${n}.md"
  _changed_under "devflow-plugin/skills/${n}/" && s="${s:+$s, }devflow-plugin/skills/${n}/"
  echo "  - ${n}: edited in ${s}"
done
for n in $ambiguous; do echo "  ! ${n}: BOTH source and a generated copy changed — resolve by hand."; done

if [[ "$MODE" == "check" ]]; then
  echo ""
  echo "These generated-tree edits will be LOST on the next 'make skills-sync'. Run 'make skills-guard' to fold them into skills/<name>/ before creating the PR."
  exit 1
fi

# ── Fold misplaced edits back into the source ──
echo ""
_desc_from_cmd() {
  awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1 && sub(/^description:[[:space:]]*/,""){sub(/^\[[0-9]+\.[0-9]+\.[0-9]+\][[:space:]]*/,""); print; exit}' "$1"
}
_body_after_fm() {
  awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; if(n==2){b=1; next}} b{print}' "$1"
}

for n in $misplaced; do
  cmd_ch=false; skl_ch=false
  _changed_under "devflow-plugin/commands/${n}.md" && cmd_ch=true
  _changed_under "devflow-plugin/skills/${n}/" && skl_ch=true

  if $cmd_ch && $skl_ch; then
    echo "  ! ${n}: both command and plugin skill hand-edited — cannot auto-fold; resolve by hand."
    ambiguous="$ambiguous $n"
    continue
  fi

  if $skl_ch; then
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      case "$p" in devflow-plugin/skills/"$n"/*) : ;; *) continue ;; esac
      rel="${p#devflow-plugin/skills/$n/}"
      mkdir -p "$(dirname "skills/${n}/${rel}")"
      cp "$p" "skills/${n}/${rel}"
      echo "  ↩ folded ${p} -> skills/${n}/${rel}"
    done <<< "$changed"
  fi

  if $cmd_ch; then
    cmd="devflow-plugin/commands/${n}.md"; src="skills/${n}/SKILL.md"
    new_desc="$(_desc_from_cmd "$cmd")"
    {
      printf -- '---\n'
      printf 'name: %s\n' "$n"
      printf 'description: %s\n' "$new_desc"
      printf -- '---\n'
      _body_after_fm "$cmd"
    } > "$src"
    echo "  ↩ folded ${cmd} -> ${src} (name preserved; description + body taken from command)"
  fi
done

echo ""
echo "skills-guard: regenerating all generated copies from source..."
bash scripts/build-skills.sh >/dev/null
bash scripts/build-flows.sh >/dev/null
echo "skills-guard: done. Review 'git diff skills/' then re-stage."

if [[ -n "$(echo "$ambiguous" | xargs 2>/dev/null || true)" ]]; then
  echo ""
  echo "skills-guard: NOT auto-resolved:${ambiguous}"
  echo "Put the authoritative version in skills/<name>/SKILL.md, then run 'make skills-sync'."
  exit 1
fi
