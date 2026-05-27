---
name: brainstorming
description: Devflow wrapper for the upstream brainstorming skill. Use when starting any creative work — creating features, building components, adding functionality, or modifying behavior — to explore user intent, requirements, and design before implementation. Always invoke `/devflow:brainstorming` rather than the upstream skill directly so devflow can layer in project-specific behavior (recall hooks, phase-handoff entry points) without callers ever needing to know about the upstream.
---

You are the devflow wrapper for the upstream brainstorming workflow. The wrapper exists so the rest of the devflow pipeline (new-feature, spec-feature, etc.) has a single canonical entry point (`/devflow:brainstorming`) and never reaches past it to the upstream skill directly.

## Steps

1. **Delegate to the upstream brainstorming skill.** Invoke `superpowers:brainstorming` via the Skill tool. Pass through `$ARGUMENTS` verbatim so the upstream skill receives the user's original input.

2. **Let the upstream skill drive.** Do NOT layer additional questions, gates, or prompts on top of the upstream flow inside this wrapper — the upstream skill already runs the full requirements/design/approach exploration loop with `AskUserQuestion` gates. Your job is to be a transparent pass-through.

3. **On completion, return control.** The upstream brainstorming skill's terminal state is invoking `superpowers:writing-plans`. Devflow does NOT short-circuit that — when the user is ready to spec, they invoke `/devflow:spec-feature` (devflow's spec-writing wrapper) directly. Brainstorming → spec-feature happens in the SAME session (no `phase-handoff` between them — the phase handoff fires only at spec → plan, plan → lock-tests, and lock-tests → impl boundaries).

## Why this wrapper exists

- **Single canonical entry point.** All devflow callers (new-feature.md, future skills) invoke `/devflow:brainstorming` instead of `/brainstorming` or `superpowers:brainstorming`. If devflow ever needs to layer in project context (Hindsight recall, prior-feature memory) before brainstorming starts, that layering happens here without touching call sites.
- **Consistency with the rest of the devflow pipeline.** Other devflow phases (`writing-plans`, `executing-plans`, `lock-tests`, `phase-handoff`) all have explicit devflow surface. Brainstorming gets the same treatment for symmetry.
- **Decoupling from upstream API changes.** If `superpowers:brainstorming` is renamed/moved/replaced, only this wrapper needs to update — call sites stay stable.

## Fallback if upstream is unavailable

If `superpowers:brainstorming` is not loaded in the current session (older Claude Code, plugin disabled, etc.), search the available-skills list for variants matching `*brainstorm*`. If none found, surface a clear error: `Upstream brainstorming skill not found. Verify the superpowers plugin is installed (re-run the OMC setup flow or check ~/.claude/plugins/).` Then exit — do NOT attempt to re-implement the brainstorming logic inline.

## Important

- This wrapper is intentionally thin. Resist the temptation to add custom phases here — that lives in the upstream skill, or in dedicated devflow skills (`spec-feature`, `writing-plans`, etc.).
- Do NOT auto-invoke `/devflow:spec-feature` from inside the brainstorming flow — the upstream skill's HARD-GATE forbids invoking implementation skills before user-approved design exists, and devflow respects that.

$ARGUMENTS
