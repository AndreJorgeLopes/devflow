# Agent Deck Configuration

Configuration template for [Agent Deck](https://github.com/anthropics/agent-deck) — a unified manager for AI coding agents.

## Setup

1. **Install Agent Deck** (if not already installed):

   ```bash
   brew install agent-deck
   ```

2. **Initialize in your project** (handled automatically by `devflow init`):

   ```bash
   devflow init
   ```

   This copies `config.toml.tmpl` to your project as `.agent-deck/config.toml` with placeholders replaced.

3. **Manual setup** (if configuring without devflow):
   ```bash
   cp config.toml.tmpl ~/.config/agent-deck/config.toml
   # Edit the file: replace {{PROJECT_NAME}} and {{PROJECT_ROOT}} with actual values
   ```

## What's Configured

| Section         | Purpose                                                                                 |
| --------------- | --------------------------------------------------------------------------------------- |
| `profiles`      | Agent commands (Claude Code, OpenCode) — set `default = true` on your preferred agent   |
| `mcp`           | MCP servers managed by Agent Deck — Hindsight is pre-configured for persistent memory   |
| `conductor`     | Auto-responds to routine confirmations; safety patterns prevent dangerous auto-confirms |
| `notifications` | Desktop alerts when agents complete tasks, hit errors, or need input                    |
| `monitoring`    | Session logging for review and debugging                                                |

## Customization

- **Add agent profiles**: Copy a `[profiles.*]` block and adjust `command`/`args`
- **Add MCP servers**: Add `[mcp.<name>]` blocks with `command` and `args`
- **Tune conductor safety**: Add patterns to `never_confirm_patterns` for operations that should always require human approval
- **Disable features**: Set `enabled = false` on any section you don't need
