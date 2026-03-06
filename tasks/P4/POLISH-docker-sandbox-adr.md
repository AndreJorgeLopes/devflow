---
id: POLISH-docker-sandbox-adr
title: "Document Docker Disabled by Default Decision (ADR)"
priority: P4
category: polish
status: open
depends_on: []
estimated_effort: S
files_to_touch:
  - /Users/andrejorgelopes/dev/devflow/docs/decisions/001-docker-sandbox-disabled.md
---

# Document Docker Disabled by Default Decision (ADR)

## Context

Agent Deck supports running AI coding agents inside Docker sandboxed containers for security isolation. During devflow setup, the decision was made to keep Docker sandbox **disabled by default** (`default_enabled = false` in `config.toml`). This was a deliberate architectural choice based on performance, complexity, and threat model analysis — but it's not documented anywhere. If someone reviews the config and sees sandboxing disabled, they might think it was an oversight.

Architecture Decision Records (ADRs) exist to capture the "why" behind non-obvious decisions so they survive beyond the original author's memory.

## Problem Statement

The reasoning behind disabling Docker sandbox by default in agent-deck is only in the developer's head (and possibly in Hindsight memory). It needs to be written down as a formal ADR so that:

1. Future-self can recall the rationale without re-researching
2. Anyone contributing to devflow understands the tradeoff
3. The decision can be revisited with context when circumstances change (e.g., Docker on macOS gets faster, or threat model changes)

## Desired Outcome

A clean ADR document at `~/dev/devflow/docs/decisions/001-docker-sandbox-disabled.md` that follows standard ADR format and captures all 5 reasoning points.

## Implementation Guide

### Step 1: Create the directory structure

```bash
mkdir -p ~/dev/devflow/docs/decisions
```

### Step 2: Write the ADR

Create `~/dev/devflow/docs/decisions/001-docker-sandbox-disabled.md` with the following content:

````markdown
# ADR-001: Docker Sandbox Disabled by Default

**Status:** Accepted
**Date:** 2025-06-XX (replace with actual date of decision)
**Decision Makers:** Andre Jorge Lopes

## Context

Agent Deck (the TUI session wrapper in devflow's Layer 2) supports running AI coding agents inside Docker sandboxed containers. This provides security isolation — agents can't access the host filesystem, network, or credentials beyond what's explicitly mounted.

The question: should Docker sandboxing be **enabled** or **disabled** by default in devflow's agent-deck configuration?

## Decision

Docker sandbox is **disabled by default** (`default_enabled = false`). SSH key mounting is enabled (`mount_ssh = true`) for when users opt in. Users can enable sandboxing per-session via the `--sandbox` flag for untrusted or experimental tasks.

Relevant config in `~/.agent-deck/config.toml`:

```toml
[sandbox]
default_enabled = false
mount_ssh = true
```
````

## Rationale

### 1. Performance Overhead on macOS

Docker on macOS does not run natively — it runs inside a Linux VM (via Colima, OrbStack, or Docker Desktop). Every file operation and command execution from a sandboxed agent container crosses the VM boundary, adding measurable latency. For a coding agent that performs hundreds of file reads/writes per session, this compounds into significant slowdown.

On Linux hosts, this concern is reduced since Docker runs natively. This decision may be revisited if devflow expands to Linux-primary users.

### 2. Nested Docker Complexity

The primary target project (messaging) uses Docker Compose extensively for integration tests — MySQL (Aurora), DynamoDB local, and other services run in containers. A sandboxed agent container would need to interact with these host-level Docker services, requiring either:

- Docker-in-Docker (DinD) — complex, fragile, performance penalty
- Docker socket mounting (`/var/run/docker.sock`) — negates most sandboxing benefits
- Complex network bridging between sandbox and test containers

None of these options are simple or reliable. They add failure modes without proportional security benefit.

### 3. Memory Pressure

Docker Desktop/Colima allocates a fixed memory budget to the Linux VM. Running multiple sandboxed agent sessions (Agent Deck supports concurrent sessions) alongside test database containers, Hindsight daemon, and Langfuse (also Docker) would strain this budget. Memory pressure leads to OOM kills, swap thrashing, and degraded agent performance.

Typical memory landscape:

- Colima VM: 4-8 GB allocated
- Langfuse (Postgres + web): ~500 MB
- MySQL test container: ~300 MB
- DynamoDB local: ~200 MB
- Each sandboxed agent session: ~500 MB-1 GB
- Leaves little headroom for concurrent sessions

### 4. SSH and Git Credential Complexity

Sandboxed containers need SSH key access for git operations (clone, push, pull). While `mount_ssh = true` mounts the host's `~/.ssh` into the container, this is an additional integration point that can fail due to:

- SSH agent socket forwarding issues
- Key permission mismatches between host and container user
- GPG signing not available inside container
- Credential helpers (git-credential-manager) not available

Each of these requires debugging when it breaks, adding friction to the development workflow.

### 5. Low Threat Model in Target Environment

In the primary use case — a professional developer working on known, trusted repositories with vetted AI agents (Claude Code, OpenCode) — the threat model is low:

- The agent operates on code the developer controls
- The agent's actions are reviewed before commit/push
- The agent doesn't execute untrusted third-party code
- The host machine is a personal development machine, not a production server

The security benefit of sandboxing is proportional to the trust level of the agent and codebase. In this high-trust environment, the overhead cost exceeds the security value.

## Consequences

### Positive

- Zero Docker overhead for agent sessions — native filesystem performance
- No nested Docker complexity — test containers work without special configuration
- Lower memory footprint — more headroom for concurrent sessions and services
- Simpler debugging — fewer layers between agent and filesystem
- Faster cold starts — no container image pull/build required

### Negative

- Agents have full access to the host filesystem and network
- A compromised or misbehaving agent could read/modify files outside the project
- SSH keys, environment variables, and credentials are accessible to the agent
- Less defense-in-depth compared to sandboxed execution

### Mitigations

- Agent actions are reviewed via pre-push checks (Continue.dev) and self-review (devflow review)
- Git worktrees (Worktrunk) provide project-level isolation between concurrent tasks
- Hindsight memory provides audit trail of agent actions
- Users can opt-in to sandboxing via `--sandbox` flag when working with untrusted code
- Agent Deck's Conductor mode monitors agent behavior in real-time

## Alternatives Considered

1. **Sandbox enabled by default, opt-out**: Rejected due to performance and complexity costs being the common case, not the exception.
2. **Lightweight sandboxing (namespaces, bubblewrap)**: Not supported by Agent Deck. Would require custom implementation.
3. **Project-level sandboxing config**: Allow per-project `.agent-deck.toml` to enable sandboxing for specific repos. Viable future enhancement but not needed now.

## Review Trigger

Revisit this decision if:

- Docker on macOS achieves native filesystem performance (e.g., via VirtioFS improvements)
- Agent Deck adds lightweight sandboxing options (namespaces, not full Docker)
- Devflow is used in lower-trust environments (open-source contributions, untrusted agents)
- A security incident occurs related to unsandboxed agent access

````

### Step 3: Add to devflow git

```bash
cd ~/dev/devflow
git add docs/decisions/001-docker-sandbox-disabled.md
git commit -m "docs: ADR-001 document Docker sandbox disabled by default decision"
````

## Acceptance Criteria

- [ ] `~/dev/devflow/docs/decisions/` directory exists
- [ ] `001-docker-sandbox-disabled.md` exists with complete ADR content
- [ ] ADR covers all 5 reasoning points (performance, nested Docker, memory, SSH/git, threat model)
- [ ] ADR follows standard format: Context, Decision, Rationale, Consequences, Alternatives
- [ ] ADR includes the actual config snippet (`default_enabled = false`, `mount_ssh = true`)
- [ ] ADR includes "Review Trigger" section for when to revisit
- [ ] ADR includes both positive and negative consequences
- [ ] ADR includes mitigations for the negative consequences
- [ ] File is committed to the devflow git repo

## Technical Notes

- ADR numbering starts at 001. Future ADRs increment: 002, 003, etc.
- The `docs/decisions/` path follows common ADR conventions (adr-tools, MADR)
- The date in the ADR should reflect when the decision was actually made, not when the ADR was written. If unknown, use the approximate date devflow was set up.
- The ADR references `config.toml` fields — if the config format changes, the ADR should be updated
- This ADR is about the **default** setting. It explicitly preserves the ability to opt-in via `--sandbox`

## Verification

```bash
# Verify file exists
test -f ~/dev/devflow/docs/decisions/001-docker-sandbox-disabled.md && echo "OK" || echo "MISSING"

# Verify key sections exist
grep -c "## Context\|## Decision\|## Rationale\|## Consequences\|## Alternatives" \
  ~/dev/devflow/docs/decisions/001-docker-sandbox-disabled.md
# Should return 5

# Verify all 5 reasoning points
grep -c "Performance\|Nested Docker\|Memory Pressure\|SSH\|Threat Model" \
  ~/dev/devflow/docs/decisions/001-docker-sandbox-disabled.md
# Should return >= 5

# Verify git tracking
cd ~/dev/devflow && git ls-files docs/decisions/
# Should list 001-docker-sandbox-disabled.md
```
