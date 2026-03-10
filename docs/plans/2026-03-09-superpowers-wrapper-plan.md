# Superpowers Wrapper Architecture — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a wrapper layer so devflow can extend superpowers skills without modifying upstream files, starting with the writing-plans agent-deck handoff.

**Architecture:** Thin wrapper skills in `skills/superpowers-wrappers/` use event-based triggers to extend superpowers behavior. Priority enforced via `~/.claude/CLAUDE.md` (user-global). Init.sh manages symlinks and template updates.

**Tech Stack:** Markdown skills, bash (init.sh), git

---

### Task 1: Create the writing-plans wrapper skill

**Files:**
- Create: `skills/superpowers-wrappers/writing-plans.md`

**Step 1: Create the wrapper directory and skill file**

Create `skills/superpowers-wrappers/writing-plans.md` with the following content:

```markdown
---
description: Extends superpowers:writing-plans with agent-deck parallel session handoff for devflow workflows.
---

This skill extends `superpowers:writing-plans`. Follow the superpowers skill completely.
When the following events occur, apply these additions:

## After: Plan execution handoff — Parallel Session chosen

When the user chooses the "Parallel Session" execution option, apply these steps
**in addition to** what superpowers provides:

### Manual command (always show first)

Print the manual command the user can run in a new terminal (same worktree directory):

    To continue manually in a new terminal, run:

      cd <current-worktree-path>
      claude --resume no -p "Read the plan at docs/plans/<plan-filename>.md and use superpowers:executing-plans to implement it task-by-task."

### Agent-deck auto-launch (offer after manual command)

Ask: **"Want me to launch this automatically via agent-deck?"**

If yes:

1. Run `agent-deck group list --json` and parse the JSON output
2. Collect all groups and subgroups, **filtering out** any named `DONE` or `done` (case-insensitive)
3. Present the filtered list with a numbered menu, plus **"No group (root level)"**
4. **CRITICAL: Use the exact group `path` from the JSON output** (e.g., `devflow`, not `Devflow`). The non-JSON display capitalizes names, but group names are case-sensitive. Using the wrong case creates a duplicate group.
5. Determine the session title: prefer the **ticket/feature ID** from the branch name (e.g., `MES-1234` from `feat/MES-1234-some-feature`) or the branch name itself. Append ` — Implementation` as suffix.
6. After the user picks a group (or root), run:

    agent-deck launch <current-worktree-path> \
      --no-parent \
      --no-wait \
      -t "<ticket-or-branch> — Implementation" \
      -g "<chosen-group-path-from-json>" \
      -m "Read the plan at docs/plans/<plan-filename>.md and use superpowers:executing-plans to implement it task-by-task."

   If "No group" was chosen, omit `-g` entirely.

7. **IMPORTANT:** Use the current worktree path as the positional argument — do NOT use `--worktree`, as the worktree already exists.
8. Confirm the session was created and tell the user to attach via agent-deck TUI or `agent-deck session attach "<session-name>"`.
```

**Step 2: Verify the file was created**

Run: `cat skills/superpowers-wrappers/writing-plans.md | head -5`
Expected: The frontmatter with `description:` line

**Step 3: Commit**

```bash
git add skills/superpowers-wrappers/writing-plans.md
git commit -m "feat(skills): add writing-plans wrapper extending superpowers with agent-deck handoff"
```

---

### Task 2: Create the devflow command for writing-plans

**Files:**
- Create: `devflow-plugin/commands/writing-plans.md`

**Step 1: Create the command file**

Create `devflow-plugin/commands/writing-plans.md` — this is the `/devflow:writing-plans` slash command that wraps the superpowers skill:

```markdown
---
description: [devflow v0.1.0] Write an implementation plan — extends superpowers:writing-plans with agent-deck parallel session handoff.
---

Use the `superpowers:writing-plans` skill to create the implementation plan.

After the plan is written, also follow the `devflow:writing-plans` skill extension
for the parallel session handoff (agent-deck auto-launch support).

$ARGUMENTS
```

**Step 2: Verify**

Run: `cat devflow-plugin/commands/writing-plans.md | head -5`
Expected: Frontmatter with `[devflow v0.1.0]` badge

**Step 3: Commit**

```bash
git add devflow-plugin/commands/writing-plans.md
git commit -m "feat(commands): add /devflow:writing-plans command wrapping superpowers skill"
```

---

### Task 3: Update the skills registry

**Files:**
- Modify: `skills/registry.json`

**Step 1: Add the superpowers-wrappers category to the registry**

Add a new entry to the `skills` array in `skills/registry.json`:

```json
{
  "name": "writing-plans",
  "description": "Extends superpowers:writing-plans with agent-deck parallel session handoff",
  "category": "superpowers-wrappers",
  "layer": 5,
  "files": ["superpowers-wrappers/writing-plans.md"]
}
```

Insert it after the last entry (dependency-update).

**Step 2: Verify the JSON is valid**

Run: `python3 -c "import json; json.load(open('skills/registry.json'))"`
Expected: No output (valid JSON)

**Step 3: Commit**

```bash
git add skills/registry.json
git commit -m "feat(registry): add superpowers-wrappers category with writing-plans entry"
```

---

### Task 4: Add skill priority rule to CLAUDE.md template

**Files:**
- Modify: `templates/CLAUDE.md.tmpl`

**Step 1: Add the skill priority section**

Add the following section to `templates/CLAUDE.md.tmpl`, after the "## Worktree Workflow" section (before "## Starting Feature Work"):

```markdown
## Skill Extensions (Superpowers Wrappers)

Devflow extends some superpowers skills with project-specific behavior (e.g., agent-deck integration).

When both a `devflow:` and a `superpowers:` skill exist with the same name (e.g., `devflow:writing-plans` and `superpowers:writing-plans`):

1. **Invoke the superpowers skill first** — it provides the core workflow
2. **Then apply the devflow extension** — it adds devflow-specific behavior at the appropriate points
3. The devflow extension uses event-based triggers ("after X happens, also do Y") — it does not replace the superpowers skill

Available wrappers:
- `devflow:writing-plans` — adds agent-deck parallel session handoff after plan completion
```

**Step 2: Verify the template is well-formed**

Run: `grep -c "Skill Extensions" templates/CLAUDE.md.tmpl`
Expected: `1`

**Step 3: Commit**

```bash
git add templates/CLAUDE.md.tmpl
git commit -m "feat(templates): add skill priority rule for superpowers wrappers"
```

---

### Task 5: Update init.sh to symlink superpowers wrappers

**Files:**
- Modify: `lib/init.sh:372-419` (section 6)

**Step 1: Add superpowers-wrappers symlink after existing skills symlink**

In `lib/init.sh`, inside the `# ── 6. Install devflow commands & skills` section, after the skills symlink block (after line 416), add:

```bash
    # Superpowers wrappers symlink
    local wrappers_link="${HOME}/.claude/skills/devflow-superpowers-wrappers"
    local wrappers_target="${root}/skills/superpowers-wrappers"
    if [[ -L "${wrappers_link}" ]]; then
      local current_wrappers_target
      current_wrappers_target="$(readlink "${wrappers_link}")"
      if [[ "${current_wrappers_target}" == "${wrappers_target}" ]]; then
        ok "Superpowers wrappers symlink healthy (${wrappers_link})"
      else
        ln -sfn "${wrappers_target}" "${wrappers_link}"
        ok "Superpowers wrappers symlink updated"
      fi
    elif [[ ! -e "${wrappers_link}" ]]; then
      ln -sfn "${wrappers_target}" "${wrappers_link}"
      ok "Superpowers wrappers installed (~/.claude/skills/devflow-superpowers-wrappers)"
    else
      skip "Superpowers wrappers path exists but is not a symlink — skipping"
    fi
```

**Step 2: Verify init.sh has no syntax errors**

Run: `bash -n lib/init.sh`
Expected: No output (valid syntax)

**Step 3: Commit**

```bash
git add lib/init.sh
git commit -m "feat(init): symlink superpowers-wrappers skills directory during init"
```

---

### Task 6: Update live ~/.claude/CLAUDE.md with skill priority rule

**Files:**
- Modify: `~/.claude/CLAUDE.md`

**Step 1: Add the skill priority section to the live CLAUDE.md**

Since `devflow init` only appends the template on first run (or if the devflow section is missing), we need to add the new section to the live `~/.claude/CLAUDE.md` manually. Add the same "Skill Extensions" section from Task 4, placing it after "## Worktree Workflow" and before "## Starting Feature Work".

**Step 2: Verify it's present**

Run: `grep "Skill Extensions" ~/.claude/CLAUDE.md`
Expected: `## Skill Extensions (Superpowers Wrappers)`

**Step 3: Verify AGENTS.md follows via symlink**

Run: `grep "Skill Extensions" ~/.claude/AGENTS.md`
Expected: Same output (symlink)

No git commit needed — this is a user config file, not in the repo.

---

### Task 7: Revert upstream superpowers modification

**Files:**
- Revert: `~/.claude/plugins/cache/claude-plugins-official/superpowers/4.3.1/skills/writing-plans/SKILL.md`

**Step 1: Reset the superpowers plugin cache to upstream**

```bash
cd ~/.claude/plugins/cache/claude-plugins-official/superpowers/4.3.1
git reset --hard HEAD~1
```

**Step 2: Verify the revert**

Run: `cd ~/.claude/plugins/cache/claude-plugins-official/superpowers/4.3.1 && git log --oneline -1`
Expected: `e4a2375 Merge pull request #524 from abzhaw/main` (the upstream commit, NOT our local one)

**Step 3: Verify the Execution Handoff section is back to upstream**

Run: `grep "agent-deck" ~/.claude/plugins/cache/claude-plugins-official/superpowers/4.3.1/skills/writing-plans/SKILL.md`
Expected: No output (agent-deck references removed)

No git commit needed — this is outside the devflow repo.

---

### Task 8: Run the symlink setup for this worktree

**Step 1: Create the superpowers-wrappers symlink manually (since we can't run full init)**

```bash
ln -sfn /Users/andrejorgelopes/dev/devflow.feat-wrap-superpowers-skills/skills/superpowers-wrappers \
  ~/.claude/skills/devflow-superpowers-wrappers
```

**Step 2: Verify the symlink**

Run: `ls -la ~/.claude/skills/devflow-superpowers-wrappers`
Expected: Symlink pointing to the worktree's `skills/superpowers-wrappers/`

Run: `ls ~/.claude/skills/devflow-superpowers-wrappers/`
Expected: `writing-plans.md`

No commit needed — local setup.

---

### Task 9: Final verification

**Step 1: Verify all devflow repo changes**

Run: `git log --oneline main..HEAD`
Expected: 5 commits (chore + design doc + tasks 1-5)

**Step 2: Verify the wrapper skill is discoverable**

Run: `ls ~/.claude/skills/devflow-superpowers-wrappers/writing-plans.md`
Expected: File exists

**Step 3: Verify superpowers is clean upstream**

Run: `cd ~/.claude/plugins/cache/claude-plugins-official/superpowers/4.3.1 && git status`
Expected: Clean working tree, no local commits ahead of upstream

**Step 4: Verify CLAUDE.md has priority rule**

Run: `grep -A2 "Skill Extensions" ~/.claude/CLAUDE.md`
Expected: The skill extensions section with wrapper instructions

**Step 5: Commit a final verification note (optional)**

No commit needed unless something was fixed during verification.
