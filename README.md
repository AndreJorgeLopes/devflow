<div align="center">

# devflow

**The 5-layer AI dev environment that gives your coding agents persistent memory, isolated worktrees, automated code review, and full observability — from a single `devflow init`.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25.svg)](bin/devflow)
[![Version](https://img.shields.io/badge/Version-0.1.0-orange.svg)](Makefile)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Plugin-7c3aed.svg)](devflow-plugin/)
[![OpenCode](https://img.shields.io/badge/OpenCode-Compatible-059669.svg)](templates/CLAUDE.md.tmpl)

</div>

---

## The Problem

AI coding agents start every session with amnesia. They don't remember what you decided yesterday, can't review their own code before pushing, and have no isolation between concurrent tasks. You end up babysitting: re-explaining context, manually running checks, juggling branches, and losing hard-won decisions to the void between sessions.

## The Solution

devflow composes 6 independent tools into one CLI that runs alongside your AI agent. One command (`devflow init`) sets up persistent memory across sessions, git worktree isolation per feature, local AI-powered code review, process discipline via skills, session orchestration, and self-hosted tracing — all running on your machine, nothing phoning home. **You stay in control. Agents get better context, guardrails, and memory.**

## What Makes It Different

- **Memory that persists across sessions** — Hindsight's 3-tier memory (mental models, observations, facts) means your agent recalls past decisions, patterns, and mistakes without you repeating them. 29 MCP tools for recall, retain, and reflect.
- **One command, five layers** — `devflow init` installs tools, configures MCP servers, registers hooks, sets up skills, and seeds memory. No manual wiring. Idempotent — safe to re-run.
- **Zero build dependencies** — Pure Bash CLI. No Node, Python, or Go build step. Works with what's already on your macOS dev machine.
- **Agent-agnostic** — Works with Claude Code, OpenCode, or any tool that reads CLAUDE.md and speaks MCP. Skills and hooks adapt to your CLI.
- **Local-first, privacy-first** — Memory, code review, and observability all run on your machine. Langfuse is self-hosted. No data leaves your laptop.

---

## Architecture

devflow orchestrates 5 independent layers. Each tool works standalone; devflow wires them together.

| Layer | Tool | What It Does | Runtime |
|:-----:|------|-------------|---------|
| 1 | [**Hindsight**](https://github.com/vectorize-io/hindsight) | 3-tier persistent memory via MCP (mental models, observations, facts) | Local daemon (`uvx`) |
| 2 | [**Worktrunk**](https://github.com/max-sixty/worktrunk) | Git worktree lifecycle — `wt step copy-ignored` eliminates cold starts | Homebrew |
| 3 | **Code Review** | Local pre-push AI review via individual markdown check rules | `claude` / `opencode` |
| 4 | **CLAUDE.md + Skills** | Process discipline baked into agent config. 18 slash commands | Files |
| 5 | [**Langfuse**](https://github.com/langfuse/langfuse) | Multi-agent tracing, MCP call spans, cost tracking. Self-hosted | Docker |

```mermaid
graph TD
    CLI["devflow CLI"]

    subgraph L1 ["Layer 1 — Memory"]
        HS["Hindsight<br/>:8888 API · :9999 UI"]
    end

    subgraph L2 ["Layer 2 — Isolation"]
        WT["Worktrunk<br/>git worktrees"]
    end

    subgraph L3 ["Layer 3 — Code Review"]
        CR["devflow check<br/>.devflow/checks/*.md"]
        RV["devflow review<br/>local or PR/MR URL"]
    end

    subgraph L4 ["Layer 4 — Process"]
        SK["18 Skills<br/>slash commands"]
        HK["3 Hooks<br/>auto-guards"]
    end

    subgraph L5 ["Layer 5 — Observability"]
        LF["Langfuse<br/>:3100 UI"]
    end

    CLI --> HS
    CLI --> WT
    CLI --> CR
    CLI --> RV
    CLI --> SK
    CLI --> LF
    HK -->|"guards"| SK

    classDef mem fill:#7c3aed,color:#fff,stroke:#5b21b6
    classDef iso fill:#059669,color:#fff,stroke:#047857
    classDef rev fill:#d97706,color:#fff,stroke:#b45309
    classDef proc fill:#be185d,color:#fff,stroke:#9d174d
    classDef obs fill:#0891b2,color:#fff,stroke:#0e7490
    classDef cli fill:#374151,color:#fff,stroke:#1f2937

    class HS mem
    class WT iso
    class CR,RV rev
    class SK,HK proc
    class LF obs
    class CLI cli
```

### Development Workflow

From feature request to merged PR — the full lifecycle managed by devflow:

```mermaid
graph LR
    A["devflow worktree<br/>feat/X --agent"] --> B["Agent recalls<br/>Hindsight memory"]
    B --> C["Brainstorm<br/>& plan"]
    C --> D["TDD loop<br/>per task"]
    D --> E["devflow check<br/>pre-push review"]
    E --> F["Create PR/MR<br/>retain learnings"]
    F --> G["devflow done<br/>cleanup worktree"]

    classDef iso fill:#059669,color:#fff,stroke:#047857
    classDef mem fill:#7c3aed,color:#fff,stroke:#5b21b6
    classDef proc fill:#be185d,color:#fff,stroke:#9d174d
    classDef rev fill:#d97706,color:#fff,stroke:#b45309
    classDef done fill:#6b7280,color:#fff,stroke:#4b5563

    class A iso
    class B mem
    class C,D proc
    class E rev
    class F rev
    class G done
```

---

## Quick Start

### Install

**One-liner:**
```bash
curl -fsSL https://raw.githubusercontent.com/AndreJorgeLopes/devflow/main/install.sh | bash
```

**From source:**
```bash
git clone https://github.com/AndreJorgeLopes/devflow.git ~/dev/devflow
cd ~/dev/devflow && make link
```

**Prerequisites:** git, tmux, Homebrew (macOS). Recommended: Docker CLI + runtime, Claude Code or OpenCode, uv. Optional: [defuddle](https://github.com/kepano/defuddle) (`npm install -g defuddle`) for clean web-page fetching in `/devflow:review-document`. Without it, web URLs fall back to `WebFetch`.

### First Run

```bash
# 1. Initialize — installs tools, configures MCP, sets up skills & plugins
devflow init ~/projects/myapp

# 2. Start memory daemon + observability
uvx hindsight-embed daemon start
devflow up

# 3. Seed memory from project files
devflow seed

# 4. Verify all 5 layers are healthy
devflow status

# 5. Start a feature in an isolated worktree
devflow worktree feat/add-auth --agent claude

# 6. Run pre-push code review
devflow check
```

---

## CLI Reference

```
USAGE
  devflow <command> [options]

CORE
  init [dir]                    Initialize project with all 5 layers
  status                        Health check across all layers
  version                       Print version

SERVICES
  up                            Start Docker services (Hindsight + Langfuse)
  down                          Stop Docker services
  restart                       Restart Docker services

WORKFLOW
  worktree <name> [--agent]     Create worktree, optionally launch agent session
  done <branch> [--force]       Clean up completed worktree + session
  clean [--dry-run] [--all]     Remove all merged worktrees

CODE REVIEW
  check                         Run review checks on current diff
  review [<pr-url>]             Review local diff or fetch PR/MR by URL

MEMORY
  seed [dir]                    Seed Hindsight memory from project files

SKILLS
  skills list                   Browse available skills with install status
  skills install <name>         Copy skill to .claude/commands/
  skills remove <name>          Remove skill from project
  skills convert                Convert skills to plugin format
```

---

## Skills & Commands

`devflow init` installs 27 slash commands. Type `/devflow:` in Claude Code to see them all.

| Skill | Layer | What It Does |
|-------|:-----:|-------------|
| `/devflow:new-feature` | Memory + Process | Start feature — recall context, scope check, brainstorm |
| `/devflow:finish-feature` | Review + Memory | Verify, commit, create PR/MR, retain learnings, cleanup |
| `/devflow:create-pr` | Review + Memory | Self-review + code checks + PR creation pipeline |
| `/devflow:pre-push-check` | Review + Process | Full pre-push review against check rules + CLAUDE.md |
| `/devflow:review` | Review | Multi-perspective code review of a PR/MR or local diff |
| `/devflow:review-document` | Review | Multi-perspective prose review (KB/RFC/spike/runbook/PRD) on Google Docs, Confluence, local files, or URLs |
| `/devflow:spec-feature` | Memory + Process | Architecture recall + spec doc + task breakdown |
| `/devflow:architecture-decision` | Memory + Process | Document ADR, retain in Hindsight, update CLAUDE.md |
| `/devflow:best-roi-task` | Process | Find highest ROI task in a Jira Epic |
| `/devflow:scope-check` | Process | Surface ambiguities and assumptions before coding |
| `/devflow:retain-learning` | Memory | Store a discovery into persistent memory |
| `/devflow:reflect-session` | Memory | End-of-session reflection and consolidation |
| `/devflow:session-summary` | Observability | Generate summary for Langfuse tracing |
| `/devflow:writing-plans` | Process | Write implementation plan with parallel session handoff |
| `/devflow:pr-strategy` | Process | View or reset PR description strategy |
| `/devflow:task-complete` | Process | Mark task done, move to done/, retain learnings |
| `/devflow:task-prioritize` | Process | Move task between priority folders (P0-P4) |
| `/devflow:dependency-update` | Process | Check if project dependencies need updating |
| `/devflow:update-visualizations` | Process | Analyze changes, update architecture diagrams |
| `/devflow:verify-first` | Process | Ground-truth every technical claim against the real system before relying on it — run the probe, docs are not verification |
| `/devflow:visualizations-config` | Process | Configure diagram output preferences (Mermaid or Excalidraw) |
| `/devflow:render-diagram` | Process | Author + render an Excalidraw diagram (pure-node, no browser/MCP), show it inline via the Read tool, embed in docs |

You can also install skills per-project without the plugin:

```bash
devflow skills list                    # Browse the 28 skills
devflow skills install new-feature     # Copy to .claude/commands/
```

---

## What `devflow init` Does

A single command that sets up all 5 layers (idempotent — safe to re-run):

```mermaid
graph TD
    INIT["devflow init ~/myapp"]

    subgraph Step1 ["1. Prerequisites"]
        CHECK["Verify git, tmux, brew, docker"]
    end

    subgraph Step2 ["2. Install Tools"]
        TOOLS["Worktrunk + uv + Hindsight"]
    end

    subgraph Step3 ["3. User Config"]
        USER["~/.claude/CLAUDE.md<br/>~/.claude/AGENTS.md<br/>Trust configuration"]
    end

    subgraph Step4 ["4. Project Config"]
        PROJECT[".worktrunk.toml<br/>.devflow/checks/ (5 review rules)"]
    end

    subgraph Step5 ["5. Plugins & Marketplace"]
        PLUGINS["Worktrunk plugin<br/>devflow marketplace (auto-update)"]
    end

    subgraph Step6 ["6. Commands & Skills"]
        CMDS["18 slash commands<br/>devflow-recall skill"]
    end

    subgraph Step7 ["7. MCP + Hooks"]
        MCP["Hindsight MCP server<br/>3 Claude Code hooks"]
    end

    INIT --> Step1 --> Step2 --> Step3 --> Step4 --> Step5 --> Step6 --> Step7

    classDef initStyle fill:#374151,color:#fff,stroke:#1f2937
    class INIT initStyle
```

**User-scoped** (applies across all projects): CLAUDE.md, AGENTS.md, MCP config, plugins, hooks.
**Project-scoped** (per-repo): `.worktrunk.toml`, `.devflow/checks/`.

All user-scoped files use `<!-- devflow -->` markers to detect existing sections and skip on re-run.

---

## Plugin Distribution

devflow is distributed as a **Claude Code plugin** via its own marketplace.

### For End Users

`devflow init` configures the GitHub-source marketplace with **auto-update enabled** — this is the default for **everyone, including maintainers**. On every Claude Code session start the plugin checks GitHub and pulls the latest published version, so a merge to `main` (which auto-releases) reaches your install with no manual step. A `SessionStart` hook also warns if your install is behind the latest release.

```bash
# Manual install (if not using devflow init)
claude plugin marketplace add AndreJorgeLopes/devflow
claude plugin install devflow@devflow-marketplace
```

### For Contributors (local dev mode — explicit opt-in)

Local dev mode uses a **local directory source + symlinks** so your uncommitted edits are reflected immediately. It is an **explicit opt-in** — `devflow init` no longer auto-selects it just because you are inside the repo (that used to strand maintainers on a stale local copy that never saw merged releases).

Opt in with any of: `devflow init --dev`, `DEVFLOW_DEV=1 devflow init`, or `make plugin-dev`.

> **Local dev mode does NOT auto-update from origin.** The plugin mirrors your working tree, not the remote. To pick up merged releases you must `git pull` the clone (and `make install` for the CLI). When you are done iterating, run `make plugin-unlink && devflow init` to return to the auto-updating GitHub-source install.

```bash
git clone https://github.com/AndreJorgeLopes/devflow.git ~/dev/devflow
cd ~/dev/devflow
make link              # CLI binary
devflow init --dev     # explicit opt-in to local dev mode (symlinks)
```

| Mode | How to get it | Source | Discovery | Auto-Update from origin |
|------|---------------|--------|-----------|:-----------------------:|
| Default (all users + maintainers) | `devflow init` | GitHub (`AndreJorgeLopes/devflow`) | Plugin cache | Yes (session-start pull) |
| Local dev (opt-in) | `devflow init --dev` / `make plugin-dev` | Local directory | Symlinks | No (mirrors working tree; `git pull` to update) |

---

## Hindsight (Memory)

Hindsight runs as a **local daemon** — no Docker needed for memory.

`devflow init` prompts you to choose an LLM provider:

| Provider | API Key? | Notes |
|----------|:--------:|-------|
| `claude-code` | No | Uses your Claude Code subscription |
| `openai-codex` | No | Uses your OpenAI Codex subscription |
| `anthropic` | Yes | Direct Anthropic API |
| `openai` | Yes | Direct OpenAI API |
| `groq` | Yes | Fast inference |
| `ollama` | No | Free, runs locally |

```bash
# Daemon lifecycle
uvx hindsight-embed daemon start
uvx hindsight-embed daemon stop
uvx hindsight-embed daemon status

# Test memory
uvx hindsight-embed memory retain default "TypeScript project uses strict mode"
uvx hindsight-embed memory recall default "project conventions"

# Change provider later
uvx hindsight-embed profile set-env main HINDSIGHT_API_LLM_PROVIDER claude-code
```

**API:** `localhost:8888` | **MCP:** `localhost:8888/mcp/` | **UI:** `localhost:9999`

---

## Code Review Checks

`devflow init` installs 5 review rules to `.devflow/checks/`:

| Rule | What It Catches |
|------|----------------|
| `handler-factory.md` | Lambda handlers without factory wrappers |
| `structured-logging.md` | Raw `console.log` instead of structured logger |
| `joi-validation.md` | Missing Joi input validation |
| `no-any-types.md` | `any` types and unsafe assertions |
| `error-handling.md` | Improper error handling patterns |

Each rule is a markdown file containing the review prompt. `devflow check` sends your current diff plus each rule to an AI CLI:

```bash
devflow check                         # Review current diff
devflow review                        # Self-review against CLAUDE.md
devflow review https://github.com/org/repo/pull/42  # Review a PR by URL
```

Uses `claude --print` (primary) or `opencode run` (fallback). Override with `DEVFLOW_REVIEW_CLI`.

These run **locally only** — they never appear as PR bot comments. Add your own rules by creating markdown files in `.devflow/checks/`.

---

## Docker Services

`devflow up` starts Langfuse via Docker Compose:

```bash
colima start               # or Docker Desktop / orbstack
devflow up                 # Start Langfuse on :3100
devflow status             # Verify health
devflow down               # Stop services
```

| Service | Image | Port | Purpose |
|---------|-------|:----:|---------|
| `langfuse-web` | `langfuse/langfuse:2` | 3100 | Tracing UI |
| `langfuse-db` | `postgres:15` | — | Langfuse database |

---

## Hooks

devflow registers 3 Claude Code hooks via `devflow init`:

| Hook | Event | Behavior |
|------|-------|----------|
| `prompt-fetch-rebase.sh` | UserPromptSubmit | Auto-fetch origin, safe rebase, inject conflict context |
| `post-pr-continue.sh` | PostToolUse (Bash) | Detect PR/MR creation, nudge agent to continue |
| `stop-finish-prompt.sh` | Stop | No-op stub (finish-feature handled at skill level) |

Hooks use the Claude Code JSON protocol: stdin receives payload, exit codes control behavior (0 = allow, 2 = block/re-activate).

---

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DEVFLOW_ROOT` | Auto-detected | Path to devflow installation |
| `DEVFLOW_REVIEW_CLI` | `claude` | Override code review CLI (`claude` or `opencode`) |
| `HINDSIGHT_API` | `http://localhost:8888` | Hindsight API endpoint |
| `ANTHROPIC_API_KEY` | — | For Hindsight when using Anthropic provider |

### Files Created by `devflow init`

| File | Scope | Purpose |
|------|:-----:|---------|
| `~/.claude/CLAUDE.md` | User | Process discipline, memory workflow, LSP config |
| `~/.claude/AGENTS.md` | User | Symlink to CLAUDE.md |
| `~/.claude/settings.json` | User | Hooks, plugins, marketplace config |
| `.worktrunk.toml` | Project | Worktree settings |
| `.devflow/checks/*.md` | Project | Code review rules (5 defaults) |

---

## Project Structure

```
devflow/
├── bin/devflow                  # CLI entry point (routes subcommands)
├── lib/                         # Core implementations (2,740 lines of Bash)
│   ├── utils.sh                 #   Logging, VCS detection, Docker helpers
│   ├── init.sh                  #   5-layer initialization
│   ├── services.sh              #   Docker service orchestration
│   ├── check.sh                 #   Multi-CLI code review
│   ├── skills.sh                #   Skill list/install/remove/convert
│   ├── seed.sh                  #   Hindsight memory seeding
│   ├── worktree.sh              #   Git worktree + agent launch
│   ├── done.sh                  #   Cleanup after merge (3-layer squash detection)
│   ├── visualizations.sh        #   Mermaid diagram management
│   ├── watch.sh                 #   Sensitive file watchdog
│   └── hooks/                   #   Claude Code hook scripts
├── devflow-plugin/              # Claude Code plugin (marketplace-ready)
│   ├── .claude-plugin/          #   Plugin + marketplace manifests
│   ├── commands/                #   Slash commands (GENERATED from skills/)
│   └── skills/                  #   Plugin skills (GENERATED from skills/)
├── skills/                      # SOURCE OF TRUTH — 28 skills, one dir each
│   ├── registry.json            #   Skill catalog (category, layer, description)
│   └── <name>/SKILL.md          #   Authored skill; run `make skills-sync` to
│                                #   regenerate devflow-plugin/{skills,commands} + flows
├── templates/                   # Init templates (CLAUDE.md, checks, configs)
├── docker/                      # Docker Compose (Langfuse + Postgres)
├── visualizations/              # Architecture diagrams (Mermaid)
├── tests/                       # Bats test framework
├── docs/plans/                  # 12 design documents
├── tasks/                       # Backlog (P0-P4 priority folders)
├── Formula/devflow.rb           # Homebrew formula
├── install.sh                   # Curl-pipe installer
├── Makefile                     # install, link, test, plugin-dev, release
└── LICENSE                      # MIT
```

---

## Development

### Developer Setup

```bash
git clone https://github.com/AndreJorgeLopes/devflow.git ~/dev/devflow
cd ~/dev/devflow
make link          # Symlink CLI to ~/.local/bin/devflow
devflow init       # Auto-detects dev mode: uses symlinks, skips plugin install
```

In dev mode, `devflow init`:
- Sets the marketplace source to **local directory** (your edits are live)
- **Uninstalls** the plugin to avoid duplicates with symlinks
- Creates symlinks from `~/.claude/commands/devflow` to your source

### Make Targets

```bash
make install        # Install to ~/.local (end users)
make link           # Symlink binary for dev
make plugin-dev     # Symlink commands + skills for live iteration
make plugin-unlink  # Remove dev symlinks
make plugin-install # Register GitHub marketplace + install plugin
make test           # Smoke tests (binary, version, help)
make test-unit      # Bats unit tests
make release        # Create release tarball
make check-version  # Verify version consistency across all files
make check-formula  # Verify Formula SHA matches latest tarball
```

### Testing

```bash
make test           # Smoke: binary exists, version matches, help works
make test-unit      # Bats: lib/utils.sh function tests
```

Tests use [Bats](https://github.com/bats-core/bats-core) with `bats-support` and `bats-assert` submodules.

---

## License

MIT
