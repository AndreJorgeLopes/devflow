---
description: [0.20.0] Devflow wrapper for the upstream brainstorming skill. Use when starting any creative work — creating features, building components, adding functionality, or modifying behavior — to explore user intent, requirements, and design before implementation. Always invoke `/devflow:brainstorming` rather than the upstream skill directly so devflow can layer in project-specific behavior (recall hooks, phase-handoff entry points) without callers ever needing to know about the upstream.
---

You are the devflow wrapper for the upstream brainstorming workflow. The wrapper exists so the rest of the devflow pipeline (new-feature, spec-feature, etc.) has a single canonical entry point (`/devflow:brainstorming`) and never reaches past it to the upstream skill directly.

## Steps

1. **Delegate to the upstream brainstorming skill.** Invoke `superpowers:brainstorming` via the Skill tool. Pass through `$ARGUMENTS` verbatim so the upstream skill receives the user's original input.

2. **Let the upstream skill drive.** Do NOT layer additional questions, gates, or prompts on top of the upstream flow inside this wrapper — the upstream skill already runs the full requirements/design/approach exploration loop with `AskUserQuestion` gates. Your job is to be a transparent pass-through.

3. **Override the upstream terminal handoff.** The upstream brainstorming skill's documented terminal state is to invoke `superpowers:writing-plans` directly. **Devflow OVERRIDES that** — devflow's pipeline is `brainstorming → spec-feature → writing-plans` (spec lives BETWEEN brainstorming and writing-plans, not skipped). When the upstream brainstorming flow reaches its terminal state (user has approved the design + the spec doc has been written + the user has approved the written spec file), do NOT invoke `superpowers:writing-plans` or any `/writing-plans` slash command. Instead, surface this message and return control:

   ```
   Brainstorming complete — design approved + spec written and approved.

   Next step in devflow's pipeline: invoke `/devflow:spec-feature` to formalize the spec into the structured devflow spec doc (this is where the spec-feature skill takes the brainstormed design and produces `docs/specs/<feature>.md` + extracts ordered tasks). After that completes, `spec-feature` invokes `devflow:phase-handoff` which spawns a new session for the `/devflow:writing-plans` phase.

   Do NOT run `/writing-plans` or `superpowers:writing-plans` directly — devflow inserts `spec-feature` between brainstorming and writing-plans.
   ```

   Then exit. Brainstorming → spec-feature happens in the SAME session (no `phase-handoff` between them — phase-handoff fires only at spec → plan, plan → lock-tests, and lock-tests → impl boundaries). The user invokes `/devflow:spec-feature` next.

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
