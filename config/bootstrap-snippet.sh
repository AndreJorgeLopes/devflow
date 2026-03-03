#!/usr/bin/env bash
# =============================================================================
# devflow bootstrap integration snippets
# =============================================================================
#
# This file is a REFERENCE — not meant to be executed directly.
# It documents what to add to your existing bootstrap files.
#
# =============================================================================

# -----------------------------------------------------------------------------
# 1. ~/Brewfile — add these lines
# -----------------------------------------------------------------------------
: <<'BREWFILE_SNIPPET'

# AI Dev Environment (devflow)
brew "agent-deck"      # Session wrapper (if available via brew)
brew "worktrunk"       # Git worktree manager
# devflow itself installed via local tap or make install

BREWFILE_SNIPPET

# -----------------------------------------------------------------------------
# 2. ~/dev/bootstrap-macos-work.sh — add this function
# -----------------------------------------------------------------------------
: <<'BOOTSTRAP_SNIPPET'

install_devflow() {
  if command -v devflow >/dev/null 2>&1; then
    log "devflow already installed"
    return
  fi
  log "Installing devflow (AI dev environment)"
  if [[ -d "$HOME/dev/devflow" ]]; then
    make -C "$HOME/dev/devflow" install
  else
    curl -fsSL https://raw.githubusercontent.com/AndreJorgeLopes/devflow/main/install.sh | bash
  fi
}

BOOTSTRAP_SNIPPET

# -----------------------------------------------------------------------------
# 3. Shell profile (~/.zshrc) — ensure PATH includes ~/.local/bin
# -----------------------------------------------------------------------------
: <<'PROFILE_SNIPPET'

# devflow (and other ~/.local/bin tools)
export PATH="${HOME}/.local/bin:${PATH}"

PROFILE_SNIPPET
