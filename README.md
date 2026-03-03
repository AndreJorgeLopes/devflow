# devflow

AI dev environment orchestrator. Integrates 6 tools into one CLI so AI coding agents (Claude Code, OpenCode) work alongside you with persistent memory, isolated worktrees, automated code review, process discipline, and observability.

**Developer multiplier, not replacement.** You stay in control — agents get better context, guardrails, and memory.

## The 6 Layers

| #   | Layer                                                              | What it does                                                                                      | Runtime            |
| --- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- | ------------------ |
| 1   | [Hindsight](https://github.com/vectorize-io/hindsight)             | Three-tier persistent memory via MCP (L0 mental models, L1 observations, L2 facts). 29 MCP tools. | Local daemon (uvx) |
| 2   | [Agent Deck](https://github.com/asheshgoplani/agent-deck)          | TUI session wrapper with Conductor auto-monitoring, MCP socket pooling, skills management.        | Homebrew           |
| 3   | [Worktrunk](https://github.com/max-sixty/worktrunk)                | Git worktree lifecycle. `wt step copy-ignored` copies gitignored files to eliminate cold starts.  | Homebrew           |
| 4   | [Continue.dev](https://github.com/continuedev/continue) (`cn` CLI) | Local pre-push AI code review checks. Individual markdown check files per rule.                   | npm                |
| 5   | CLAUDE.md + Skills                                                 | Process discipline baked into agent config. Memory-aware templates, multi-agent coordination.     | Files              |
| 6   | [Langfuse](https://github.com/langfuse/langfuse)                   | Multi-agent tracing, MCP call spans, cost tracking. Self-hosted.                                  | Docker             |

## Install

### Quick (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/AndreJorgeLopes/devflow/main/install.sh | bash
```

### Homebrew

```bash
brew install --formula Formula/devflow.rb  # local formula
```

### From source

```bash
git clone https://github.com/AndreJorgeLopes/devflow.git ~/dev/devflow
cd ~/dev/devflow
make link  # symlinks to ~/.local/bin/devflow
```

### Prerequisites

- **Required**: git, tmux, Homebrew (macOS)
- **Recommended**: Docker CLI + runtime (colima or Docker Desktop), Claude Code or OpenCode, jq, Node.js (for `cn` CLI), uv (for Hindsight)

## Quick Start

```bash
# 1. Initialize (installs tools, configures MCP, copies templates, installs plugins)
#    Interactive prompt lets you choose LLM provider for Hindsight memory
devflow init ~/projects/myapp

# 2. Start Hindsight daemon + Docker services (Langfuse)
uvx hindsight-embed daemon start
devflow up  # starts Langfuse (Docker)

# 3. Seed Hindsight with project knowledge
devflow seed

# 4. Check status of all 6 layers
devflow status

# 5. Start a feature in an isolated worktree
devflow worktree feat/add-auth --agent claude

# 6. Run pre-push code review checks
devflow check
```

## Commands

```
devflow init [dir]              Initialize project with all 6 layers
devflow up                      Start Docker services (Hindsight + Langfuse)
devflow down                    Stop Docker services
devflow status                  Health check across all layers
devflow check                   Run Continue.dev checks on current diff
devflow review                  Self-review via Claude Code against CLAUDE.md
devflow seed [dir]              Seed Hindsight memory from project files
devflow worktree <name> [--agent]  Create worktree, optionally launch agent
devflow skills list             List available skills
devflow skills install <name>   Install skill to .claude/commands/
devflow skills remove <name>    Remove skill from project
devflow version                 Print version
devflow help                    Show help
```

## Skills Marketplace

Skills are Claude Code slash commands that integrate the 6 layers. Install them per-project:

```bash
devflow skills list           # Browse 10 available skills
devflow skills install new-feature  # Copy to .claude/commands/
```

| Skill                   | Layer        | Description                                                   |
| ----------------------- | ------------ | ------------------------------------------------------------- |
| `memory-recall`         | Hindsight    | Recall relevant memories before starting a task               |
| `retain-learning`       | Hindsight    | Retain a discovery into persistent memory                     |
| `reflect-session`       | Hindsight    | Reflect and consolidate session learnings                     |
| `pre-push-check`        | Continue.dev | Run full pre-push review pipeline                             |
| `new-feature`           | Worktrunk    | Start feature with worktree + memory recall + workspace setup |
| `finish-feature`        | Worktrunk    | Finish feature with checks, commit, merge, learning retention |
| `create-pr`             | Continue.dev | Full PR creation pipeline with self-review                    |
| `spec-feature`          | Process      | Spec a feature with architecture recall and task breakdown    |
| `architecture-decision` | Process      | Document ADR with rationale and memory retention              |
| `session-summary`       | Langfuse     | Generate session summary for observability                    |

## What `devflow init` Does

1. **Checks prerequisites** — git, tmux, Homebrew (macOS)
2. **Installs tools** — Agent Deck (brew), Worktrunk (brew), Continue.dev CLI (npm), uv (brew), Hindsight (uvx)
3. **User-scoped config** — `~/.claude/CLAUDE.md` (memory workflow, process discipline), `~/.claude/AGENTS.md` (multi-agent coordination). These apply across ALL your projects without touching the team's project-level CLAUDE.md.
4. **Project-scoped config** — `.worktrunk.toml` (worktree settings), `.continue/checks/` (code review rules). These are per-repo.
5. **Claude Code plugins** — Installs Agent Deck and Worktrunk plugins via `claude plugin`
6. **Skills** — Installs Hindsight and Agent Deck skills for both Claude Code and OpenCode
7. **Configures MCP** — Adds Hindsight as HTTP MCP server to Claude Code and/or OpenCode (user-scoped)
8. **Shell integration** — Configures Worktrunk zsh integration

All operations are idempotent — safe to run multiple times. User-scoped files use a `<!-- devflow -->` marker to detect existing sections.

## Hindsight (Memory)

Hindsight runs as a **local daemon** via `hindsight-embed` — no Docker needed for memory.

`devflow init` prompts you to choose an LLM provider:

| Provider       | API Key? | Notes                               |
| -------------- | -------- | ----------------------------------- |
| `claude-code`  | No       | Uses your Claude Code subscription  |
| `openai-codex` | No       | Uses your OpenAI Codex subscription |
| `anthropic`    | Yes      | Direct Anthropic API                |
| `openai`       | Yes      | Direct OpenAI API                   |
| `groq`         | Yes      | Fast inference                      |
| `ollama`       | No       | Free, local models                  |

```bash
# Start/stop daemon
uvx hindsight-embed daemon start
uvx hindsight-embed daemon stop
uvx hindsight-embed daemon status

# Test memory
uvx hindsight-embed memory retain default "TypeScript project uses strict mode"
uvx hindsight-embed memory recall default "project conventions"

# Change provider later
uvx hindsight-embed profile set-env main HINDSIGHT_API_LLM_PROVIDER claude-code
```

API: `localhost:8888` | MCP: `localhost:8888/mcp/`

## Docker Services

`devflow up` starts Langfuse via Docker Compose (requires Docker CLI + runtime like colima):

- **Langfuse** — Observability UI on `localhost:3100`

```bash
# Start a lightweight Docker runtime (if not using Docker Desktop)
colima start

# Start Langfuse
devflow up
```

## Continue.dev Checks

`devflow init` installs 5 pre-built check files to `.continue/checks/`:

- `handler-factory.md` — Lambda handlers must use factory wrappers
- `structured-logging.md` — No `console.log`, use structured logger
- `joi-validation.md` — All inputs validated with Joi schemas
- `no-any-types.md` — No `any` types or unsafe assertions
- `error-handling.md` — Proper error handling patterns

These are **local only** — they run on your machine before push. They never appear as PR bot comments and are invisible to teammates.

## Project Structure

```
devflow/
├── bin/devflow              # CLI entry point
├── lib/                     # Command implementations
│   ├── utils.sh             # Shared utilities
│   ├── init.sh              # devflow init
│   ├── services.sh          # devflow up/down/status
│   ├── check.sh             # devflow check
│   ├── skills.sh            # devflow skills
│   ├── seed.sh              # devflow seed
│   └── worktree.sh          # devflow worktree
├── docker/
│   ├── docker-compose.yml   # Hindsight + Langfuse
│   └── .env.example
├── templates/               # Project templates
│   ├── CLAUDE.md.tmpl
│   ├── AGENTS.md.tmpl
│   ├── .worktrunk.toml.tmpl
│   └── .continue/checks/    # 5 review check files
├── skills/                  # Skills marketplace
│   ├── registry.json
│   ├── memory-recall/
│   ├── code-review/
│   ├── worktree-flow/
│   ├── pr-pipeline/
│   ├── process-discipline/
│   └── observability/
├── config/agent-deck/       # Agent Deck config template
├── Formula/devflow.rb       # Homebrew formula
├── Makefile                 # install, link, test, release
└── install.sh               # Curl-pipe installer
```

## Design Decisions

- **Bash CLI** — Zero dependencies beyond what's already on a macOS dev machine. No Node/Python/Go build step.
- **Composition over integration** — Each layer is an independent tool. Devflow orchestrates; it doesn't replace.
- **Local-first** — Memory, review, and observability all run on your machine. Nothing phones home.
- **No Docker Desktop required** — Hindsight uses a local daemon. Langfuse needs Docker CLI + any runtime (colima, orbstack, or Docker Desktop).
- **User-scoped by default** — CLAUDE.md, AGENTS.md, MCP config, and plugins go to user scope (`~/.claude/`). Project repos stay clean for teammates.
- **Non-destructive init** — Safe to run multiple times. Appends to existing files, skips what's already there.
- **Agent-agnostic** — Works with Claude Code, OpenCode, or any tool that reads CLAUDE.md and speaks MCP.
- **Full plugin ecosystem** — Installs Claude Code plugins (Agent Deck, Worktrunk) and skills for both Claude Code and OpenCode.

## License

MIT
