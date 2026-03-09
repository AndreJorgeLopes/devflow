# Fixing Terminal Notifications in Agent-Deck (tmux)

## Problem

When Claude Code or OpenCode runs inside agent-deck's tmux sessions, desktop/terminal
notifications for "needs input" events are silently swallowed. The user never knows
a session is waiting unless they manually check.

## Root Cause (Multi-Layer)

1. **Claude Code sends OSC 9 escape sequences** (`\033]9;...`) for desktop notifications.
   tmux does not forward raw OSC sequences to the outer terminal — they need DCS
   passthrough wrapping. This is a known issue: [claude-code#19976](https://github.com/anthropics/claude-code/issues/19976).

2. **Agent-deck does not configure tmux bell options.** The tmux options `monitor-bell`,
   `bell-action`, and `visual-bell` are not set by agent-deck on the sessions it creates
   (see `/internal/tmux/tmux.go` `Start()` function). While tmux defaults _should_ work,
   the programmatic session creation may not inherit them reliably.

3. **`terminal_bell` kills macOS notification banners.** Setting `preferredNotifChannel`
   to `terminal_bell` replaces OSC 9 with just a BEL character. This gives you the dock
   badge (red circle on Ghostty icon) and title bell icon, but kills the macOS
   notification banner in the top-right corner. The correct setting is `auto`.

4. **OpenCode's "question" tool** is not detected as a "waiting" state by agent-deck
   ([agent-deck#255](https://github.com/asheshgoplani/agent-deck/issues/255)).

5. **Agent-deck only sends macOS notifications for selector-type questions** (permission
   prompts, elicitation dialogs) but NOT for general "awaiting input" state after the
   agent finishes answering. This is an agent-deck limitation.

## What This Fix Does

### 1. Keep `auto` notification channel (`~/.claude.json`)

```json
"preferredNotifChannel": "auto"
```

This preserves Claude Code's native OSC 9 desktop notifications outside tmux. Do NOT
set to `terminal_bell` — it kills macOS notification banners.

### 2. Add tmux bell options to agent-deck (`~/.agent-deck/config.toml`)

```toml
[tmux]
  [tmux.options]
    monitor-bell = "on"
    bell-action = "any"
    visual-bell = "off"
```

This ensures agent-deck's tmux sessions explicitly forward bell events to the outer
terminal. `bell-action = "any"` means bells from any window are forwarded, not just
the current one.

### 3. Add Notification hook (`~/.claude/settings.json`)

```json
{
  "hooks": [{
    "type": "command",
    "command": "bash -c 'if [ -n \"$TMUX\" ]; then printf \"\\033Ptmux;\\033\\033]9;Claude Code needs input\\007\\033\\\\\" > /dev/tty; fi; printf \"\\a\" > /dev/tty'",
    "async": true
  }]
}
```

This hook does two things on every Notification event:
- **Inside tmux**: sends a DCS-wrapped OSC 9 notification so the outer terminal
  (Ghostty/iTerm2/Kitty) shows a macOS notification banner
- **Always**: sends a BEL character for the dock badge (red circle on terminal icon)

### What you get after this fix

| Scenario | macOS banner (top-right) | Dock badge (red circle) | Title bell icon |
|----------|-------------------------|------------------------|----------------|
| Raw Claude Code (no tmux) | Yes (native OSC 9) | Yes (hook BEL) | Yes |
| Claude Code in agent-deck | Yes (DCS-wrapped OSC 9) | Yes (hook BEL) | Yes |

## Known Limitations

- **Agent-deck only notifies for selector questions**: macOS notification banners from
  agent-deck's own hook-handler only fire for permission_prompt/elicitation_dialog
  events, not for the general "waiting for input" state after answering.
- **OpenCode question tool not detected**: agent-deck doesn't recognize OpenCode's
  "question" tool as a waiting state (#255).

## Relevant Upstream Issues

| Issue | Status | Description |
|-------|--------|-------------|
| [claude-code#19976](https://github.com/anthropics/claude-code/issues/19976) | Open | Claude Code OSC notifications don't work in tmux |
| [agent-deck#211](https://github.com/asheshgoplani/agent-deck/issues/211) | Open | Native notification bridge (Slack/Telegram/desktop) |
| [agent-deck#255](https://github.com/asheshgoplani/agent-deck/issues/255) | Open | OpenCode waiting status not detected for question tool |
| [agent-deck#150](https://github.com/asheshgoplani/agent-deck/issues/150) | Closed | Added `[tmux] options` config override mechanism |

## Ideal Upstream Fixes

- **Agent-deck**: Add `monitor-bell on` + `bell-action any` as defaults in `Start()` in
  `/internal/tmux/tmux.go` — a 2-line change alongside existing options.
- **Claude Code**: Auto-detect `$TMUX` and DCS-wrap OSC 9 notifications (#19976).
- **Agent-deck**: Fix OpenCode question tool detection (#255).
- **Agent-deck**: Send macOS notifications for ALL waiting states, not just selector questions.
