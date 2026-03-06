# Agent Deck Configuration

Configuration template for [Agent Deck](https://github.com/asheshgoplani/agent-deck) — a unified manager for AI coding agents.

## Setup

1. **Install Agent Deck** (if not already installed):

   ```bash
   brew install asheshgoplani/tap/agent-deck
   ```

2. **Initialize in your project** (handled automatically by `devflow init`):

   ```bash
   devflow init
   ```

   This copies `config.toml.tmpl` to your project as `.agent-deck/config.toml` with placeholders replaced.

3. **Manual setup** (if configuring without devflow):
   ```bash
   cp config.toml.tmpl ~/.config/agent-deck/config.toml
   # Edit the file to match your environment
   ```

## What's Configured

| Section    | Purpose                                                                       |
| ---------- | ----------------------------------------------------------------------------- |
| `tools`    | Agent commands (Claude Code, OpenCode) — set `default_tool` to your preferred |
| `mcps`     | MCP servers managed by Agent Deck — Hindsight is pre-configured for memory    |
| `docker`   | Docker container settings for sandboxed sessions — disabled by default        |
| `worktree` | Git worktree integration — `subdirectory` places worktrees under project root |
| `claude`   | Claude Code-specific settings (e.g., dangerous mode for shell access)         |
| `logs`     | Session logging for review and debugging                                      |

## Customization

- **Add tool profiles**: Add `[tools.<name>]` blocks with `command` and optional `args`
- **Add MCP servers**: Add `[mcps.<name>]` blocks with `type` and `url` (http) or `command`/`args` (stdio)
- **Enable Docker**: Set `default_enabled = true` under `[docker]` for sandboxed agent sessions
- **Change worktree location**: Set `default_location` to `"sibling"` to place worktrees next to the project instead of inside it
