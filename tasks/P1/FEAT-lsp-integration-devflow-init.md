---
id: FEAT-lsp-integration-devflow-init
title: "Integrate LSP tool setup into devflow init for Claude Code and OpenCode"
priority: P1
category: features
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - lib/init.sh
  - config/lsp/lsp-setup.md
  - templates/CLAUDE.md.tmpl
  - skills/lsp-enforce/SKILL.md
---

# Integrate LSP Tool Setup into devflow init

## Context

Claude Code supports an LSP tool (`ENABLE_LSP_TOOL=1`) that provides semantic code
navigation — go-to-definition, find-references, hover types, call hierarchy — at ~900x
the speed of text-based grep. OpenCode has similar LSP integration capabilities.

Currently, LSP setup requires manual configuration: installing language servers, setting
the env var, adding auto-allow permissions, and adding CLAUDE.md instructions to prefer
LSP over Grep. This should be automated in `devflow init`.

## Problem Statement

1. **LSP is not enabled by default** in Claude Code — requires `ENABLE_LSP_TOOL=1`
2. **Language servers must be installed manually** — users don't know which ones to install
3. **No enforcement mechanism** — agents default to Grep even when LSP is available
4. **Permission prompts** interrupt flow — LSP tool should be auto-allowed
5. **OpenCode needs equivalent setup** — different config format but same concept

## Desired Outcome

`devflow init` should:

1. **Detect project languages** by scanning for `package.json` (TS/JS), `go.mod` (Go),
   `Cargo.toml` (Rust), `pyproject.toml`/`setup.py` (Python), `*.sh` (Bash), etc.

2. **Install missing language servers** based on detected languages:
   - TypeScript/JavaScript: `typescript-language-server typescript`
   - Python: `pyright` (via pip/uv)
   - Go: `gopls` (via `go install`)
   - Rust: `rust-analyzer` (via `rustup component add`)
   - Bash: `bash-language-server`

3. **Set `ENABLE_LSP_TOOL=1`** in the user's shell env file (detect ZDOTDIR or fallback
   to ~/.zshrc)

4. **Add `Lsp` to auto-allow** in `~/.claude/settings.local.json`

5. **Add LSP-first instructions** to `~/.claude/CLAUDE.md` (in the devflow section)

6. **Present interactive choice** to the user:
   ```
   Enable LSP-powered code navigation? [Y/n]
   Detected languages: TypeScript, Bash
   Will install: typescript-language-server, bash-language-server
   ```

7. **Install Claude Code LSP plugins** if available in the marketplace

8. **Configure OpenCode** with equivalent LSP settings in `~/.config/opencode/`

## Implementation Notes

### Language Detection

```bash
detect_project_languages() {
  local dir="$1"
  local langs=()
  [[ -f "$dir/package.json" || -f "$dir/tsconfig.json" ]] && langs+=("typescript")
  [[ -f "$dir/go.mod" ]] && langs+=("go")
  [[ -f "$dir/Cargo.toml" ]] && langs+=("rust")
  [[ -f "$dir/pyproject.toml" || -f "$dir/setup.py" ]] && langs+=("python")
  find "$dir" -maxdepth 2 -name "*.sh" -type f | head -1 | grep -q . && langs+=("bash")
  printf '%s\n' "${langs[@]}"
}
```

### LSP Enforcement Skill

Create a skill at `skills/lsp-enforce/SKILL.md` that:
- Reminds agents to check for Lsp tool availability before using Grep
- Provides a decision tree: Lsp first → Grep fallback
- Works for both Claude Code and OpenCode

### Grep Fallback

LSP should never fully replace Grep. Grep remains the right tool for:
- String/regex pattern searches across files
- Searching comments, documentation, or non-code content
- When LSP returns no results (language server not running, unsupported file type)
- Cross-language searches

## Acceptance Criteria

- [ ] `devflow init` detects languages and offers to install language servers
- [ ] `ENABLE_LSP_TOOL=1` is added to shell env
- [ ] `Lsp` is auto-allowed in settings.local.json
- [ ] CLAUDE.md template includes LSP-first instructions
- [ ] LSP enforcement skill works in Claude Code sessions
- [ ] OpenCode gets equivalent LSP configuration
- [ ] Grep remains available as fallback — never removed or blocked
- [ ] Bootstrap script (bootstrap-macos-work.sh) installs language servers
