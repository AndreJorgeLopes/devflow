# Devflow Project Instructions

Devflow is a 6-layer AI dev environment orchestrator (bash CLI, zero build deps).
It composes Hindsight, Agent Deck, Worktrunk, Code Review, Skills/CLAUDE.md, and Langfuse
into a unified workflow for AI coding agents (Claude Code, OpenCode).

## Project Structure

```
bin/devflow              # CLI entry point — sources all lib/*.sh, routes subcommands
lib/                     # Core command implementations (bash)
  utils.sh               # Shared utilities: logging, VCS detection, merge detection
  init.sh                # devflow init — full 6-layer setup (idempotent)
  services.sh            # devflow up/down/status — Docker service orchestration
  check.sh               # devflow check — multi-CLI code review abstraction
  skills.sh              # devflow skills — list/install/remove/convert
  seed.sh                # devflow seed — seed Hindsight from project files
  worktree.sh            # devflow worktree — wrapper around worktrunk + agent launch
  done.sh                # devflow done/clean — cleanup after PR merge
  visualizations.sh      # devflow visualizations — diagram management
  watch.sh               # devflow watch — sensitive file watchdog
  release.sh             # devflow release/version-bump — release pipeline
  hooks/                 # Claude Code hook scripts (registered via init.sh step 5d)
    prompt-fetch-rebase.sh   # UserPromptSubmit — auto-fetch + rebase
    pending-reviews-notify.sh # UserPromptSubmit — notify about stale sensitive files
    post-pr-continue.sh      # PostToolUse — nudge agent after PR creation
    stop-finish-prompt.sh    # Stop — no-op stub (finish-feature moved to skill-level)
devflow-plugin/          # Claude Code plugin (marketplace-ready)
  commands/              # 17+ markdown command/skill files (includes check-sensitive.md)
  .claude-plugin/        # Plugin metadata (plugin.json, marketplace.json)
skills/                  # Categorized skill files (NOT auto-discovered — require explicit Read)
templates/               # Init templates (CLAUDE.md.tmpl, AGENTS.md.tmpl, etc.)
tests/                   # Bats test infrastructure
  unit/utils.bats        # Unit tests for lib/utils.sh
  helpers/               # common.bash, mocks.bash, assertions.bash
docker/                  # Docker Compose for Hindsight + Langfuse
visualizations/          # Architecture diagrams (Mermaid markdown)
tasks/                   # Task backlog (P0-P4 priority folders, done/)
docs/plans/              # Dated design docs and implementation plans
```

## Development Workflow

```bash
make test                # Smoke tests (binary exists, version, help)
make test-unit           # Bats unit tests (tests/unit/)
make plugin-dev          # Symlink devflow-plugin/ → ~/.claude/commands/devflow/ (dev iteration)
make plugin-unlink       # Remove dev symlinks
make plugin-install      # Register marketplace + install (end users)
make install             # Install devflow binary to ~/.local/bin/
```

## Coding Conventions

- **Language**: Bash (all lib/ files). Portable, `set -euo pipefail` safe.
- **Function naming**: `devflow_<subcommand>()` for CLI entry points, `_helper()` with underscore prefix for internal helpers.
- **Logging**: Use `log`, `info`, `warn`, `err`, `die` from utils.sh. Status: `ok`, `fail`, `skip`. Section headers: `section`.
- **VCS detection**: Use `detect_vcs_provider()` and `get_vcs_pr_term()` from utils.sh. Guard calls under pipefail: `provider="$(detect_vcs_provider 2>/dev/null)" || provider="unknown"`.
- **Sections**: Separate logical blocks in lib files with `# ── Section Name ──` banners.
- **Tests**: Add bats tests in `tests/unit/` for new lib/utils.sh functions. Use helpers from `tests/helpers/`.

## Skill / Command Conventions

- All command descriptions include a `[devflow v0.1.0]` version badge.
- Reference Hindsight tools as "Hindsight `retain` tool" and "Hindsight `recall` tool" (not MCP tool names).
- `skills/` directory is NOT symlinked into `~/.claude/skills/` — wrappers require explicit Read instructions.
- `devflow-plugin/commands/` is the canonical source; `skills/` mirrors them in categorized subdirectories.

## Hooks Architecture

Hook scripts live in `lib/hooks/`, registered in `~/.claude/settings.json` via `devflow init` (step 5d).
Protocol: stdin receives JSON payload, exit codes control behavior (0=allow, 2=block+re-activate for Stop hooks).
- `exit 2` is ONLY valid for Stop hooks — never for UserPromptSubmit (causes infinite blocking).
- Stop hooks use `stop_hook_active` JSON field to prevent infinite re-activation loops.
- **Stop hook is a no-op.** The finish-feature prompt was removed from the stop hook because it fires on ALL agent stops (including subagents, reviews, etc.). Finish-feature transition is now handled at the skill level in `new-feature.md`.

## Feature Lifecycle

The expected feature lifecycle within a single session is: **new-feature → implement → finish-feature**.
- `new-feature` sets up context, recalls memories, runs scope-check, and starts brainstorming.
- After implementation, `finish-feature` runs verification, creates the PR/MR, retains learnings, and offers cleanup.
- On feature branches, always complete work with `/devflow:finish-feature` before ending the session.

## Sensitive File Watchdog

`devflow watch` monitors files that must stay in sync with source code changes.
- Config: `.devflow/sensitive-files.conf` (pipe-delimited, bash-native format)
- Background: `devflow watch setup` installs a 5-min cron + git post-merge hook
- In-session: finish-feature checks sensitive files before PR creation
- Manual: `/devflow:check-sensitive` runs all checks on demand
- Mechanical checks (version strings) auto-fixable; semantic checks (docs) need AI review

## Release Process

Releases are automated via GitHub Actions on push to main (`.github/workflows/release.yml`).

- **Conventional commits** determine the version bump:
  - `feat:` → minor, `fix:` → patch, `feat!:` / `BREAKING CHANGE:` → major
  - `[skip release]` in the HEAD commit message skips the release
  - `chore(release):` commits from the bot are auto-filtered (no re-trigger)
- **Version files** are updated by `scripts/bump-version.sh` (Makefile, utils.sh, plugin.json, marketplace.json, all command badges)
- **GitHub Release** created with tarball and install instructions
- **Homebrew formula** updated with new SHA/URL in the same commit
- **Preview locally:** `devflow release` shows what the next release would be
- **Manual bump:** `devflow version-bump <version>` updates all version files locally

### Auto-Reinstall

When `devflow watch setup` is run in the devflow source repo, it offers an auto-reinstall opt-in:
- Uses SHA-based staleness detection (catches all changes, not just version bumps)
- Detects install mode: symlink (`make link`), copy (`make install`), or Homebrew (warn only)
- On new commits to main, runs the appropriate `make` target automatically
- State tracked in `~/.devflow/.last-installed-sha`

## Worktree Convention

Git only allows one worktree per branch. To support multiple concurrent worktrees:
- **Never check out `main`/`master` as a tracked branch** in any worktree. Use detached HEAD instead.
- `devflow worktree` auto-detaches any worktree that has main locked before creating a new one.
- Feature worktrees always create NEW branches from main (`git worktree add <path> -b <branch> main`).
- When done, remove worktrees with `devflow done <branch>` — don't leave them lingering on main.
- This matches the pattern used by OpenCode/Superpowers, Agent-deck, and Claude Code's worktree isolation.

## Skill Interaction Rules

### MANDATORY: Use `AskUserQuestion` for all user choices

When any skill or command needs to present choices, confirmations, or selections to the user,
you **MUST** use the `AskUserQuestion` tool instead of printing a text question and waiting
for input. This applies to:

- Yes/No confirmations (e.g., "Want me to launch via agent-deck?")
- Multiple choice selections (e.g., "Which group?", "Which template?")
- Approval gates (e.g., "Proceed with these changes?")

**Why:** Text-based questions create a poor UX — the user sees a wall of text and has to
type a free-form response. `AskUserQuestion` provides clickable options, is faster to
answer, and prevents misinterpretation.

**Exception:** Open-ended questions where the user needs to provide free text (e.g.,
"Describe the feature") should still use normal text output, since `AskUserQuestion`
is designed for structured choices.
