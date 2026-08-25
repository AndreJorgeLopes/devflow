## v0.28.0 — 2026-07-30

### Features
- feat(verify-first): cover probes that pass for the wrong reason (#91)

---

## v0.27.3 — 2026-07-30

### Fixes
- fix(docker): langfuse-web healthcheck probes container IP (was falsely unhealthy) (#89)

---

## v0.27.2 — 2026-07-30

### Fixes
- fix(watch): pin scheduled entry to an absolute, stable devflow launcher (#88)

---

## v0.27.1 — 2026-07-28

### Fixes
- fix(watch): resolve install mode without PATH so launchd/cron auto-reinstall fires (#87)

---

## v0.27.0 — 2026-07-28

### Features
- feat(hooks): branch-guard — keep worktree-flow primary clones on a base branch (#86)

---

## v0.26.0 — 2026-07-28

### Features
- feat(watch): native macOS launchd scheduler (fixes unreliable user-cron) (#84)

---

## v0.25.1 — 2026-07-28

### Fixes
- fix(install): make install must replace a leftover symlink, not write through it (#71)

---

## v0.25.0 — 2026-07-28

### Features
- feat(eval): DEVFLOW_EVAL test-mode + fixture isolation — determinism gates for 5 more skills (#85)

---

## v0.24.3 — 2026-07-28

### Fixes
- fix(plugin): use record-keyed hooks schema so the plugin loads (#83)

---

## v0.24.2 — 2026-07-28

### Fixes
- fix(plugin): emit skills[] as directory paths so the plugin loads (#82)

---

## v0.24.1 — 2026-07-28

### Fixes
- fix(release): strip stale sha256 comment from Homebrew formula (#81)

---

## v0.24.0 — 2026-07-28

### Features
- feat(services): skip bundled Docker Hindsight when a native daemon owns :8888 (#80)

---

## v0.23.0 — 2026-07-28

### Features
- feat: default to GitHub-source auto-update; add version-drift session check (#79)

---

## v0.22.0 — 2026-07-28

### Features
- feat(skills): add orchestrate-epic + fast-feature devflow skills (#78)

---

## v0.21.0 — 2026-07-20

### Features
- feat(readable-doc): small summariser + readable-doc-spike (big), team style

---

## v0.20.0 — 2026-07-14

### Features
- feat(readable-doc): turnkey /devflow:readable-doc [path] reformat workflow

---

## v0.19.2 — 2026-07-14

### Fixes
- fix(build-skills): fail the skills gate on invalid YAML frontmatter

---

## v0.19.1 — 2026-07-14

### Fixes
- fix(readable-doc): repair unparseable SKILL.md frontmatter

---

## v0.19.0 — 2026-07-14

### Features
- feat(readable-doc): plannotator-safe readable-doc writing skill (#73)

---

## v0.18.0 — 2026-07-09

### Features
- feat(spec-feature): always render technical + ELI5 diagrams by default (#72)

---

## v0.17.3 — 2026-07-08

### Fixes
- fix(eval): determinism gate tests the working tree + local mirror auto-refresh (#70)

---

## v0.17.2 — 2026-07-08

### Fixes
- fix(watch): hands-off, safe auto-reinstall (install from clean origin export) (#69)

---

## v0.17.1 — 2026-07-08

### Fixes
- fix(phase-handoff): make cross-session handoff durable + self-recovering (#68)

---

## v0.17.0 — 2026-07-08

### Features
- feat(trace-review): split score into two columns - tessl review + promptfoo pass-rate (#67)

---

## v0.16.1 — 2026-07-08

### Fixes
- fix(init): atomic settings.json write + malformed-JSON recovery (#66)

---

## v0.16.0 — 2026-07-06

### Features
- feat(trace-review): score column from both sources + init telemetry/price setup + adversarial-review fixes (#64)

---

## v0.15.1 — 2026-07-06

### Fixes
- fix(resolve-repo): deterministic Repo Match Results block + gate-fidelity docs (#65)

---

## v0.15.0 — 2026-07-05

### Features
- feat(skills): mirror SKILL.md into Langfuse prompt-management (loop component b) (#63)

---

## v0.14.0 — 2026-07-05

### Features
- feat(skills): runnable determinism gate + fix broken gate providers + plugin leak (#62)

---

## v0.13.0 — 2026-07-05

### Features
- feat(trace-review): per-skill Langfuse regression report + attribution ladder + enrichment hook (#57)

---

## v0.12.0 — 2026-07-03

### Features
- feat(skills): single source of truth + generation + pre-PR rescue guard + determinism propagation (#58)

### Fixes
- fix(observability): drop container_name so Langfuse web needs no post-boot restart (#61)
- fix(observability): map Claude Code user_prompt -> input.value so Langfuse Input isn't null (#59)
- fix(observability): seed langfuse price for claude-opus-4-8[1m] (cost was 0) (#56)

---

## v0.11.0 — 2026-06-30

### Features
- feat(observability): Langfuse v3 stack + OTel collector (passive CC tracing) — has known v3 issues (#54)

---

## v0.10.0 — 2026-06-30

### Features
- feat(eval): skill-determinism audits + assertion configs + CLAUDE.md determinism guide (#53)

---

## v0.9.0 — 2026-06-29

### Features
- feat(eval): promptfoo skill-determinism harness + Langfuse observability docs (#52)

---

## v0.8.1 — 2026-06-25

### Fixes
- fix(release): bump on impr commits and surface them in release notes (#51)

---

## v0.8.0 — 2026-06-25

---

## v0.7.0 — 2026-06-23

### Features
- feat(render-diagram): ELI5 mode + auto-centered bound text + dark canvas (#47)

---

## v0.6.0 — 2026-06-23

### Features
- feat(create-pr): VCS-aware + structured description + GitLab template adaptation (#48)

---

## v0.5.0 — 2026-06-16

### Features
- feat(skills): add /devflow:verify-first verification-discipline skill (#45)

---

## v0.4.0 — 2026-06-15

### Features
- feat(flows): flow-separated marketplace + per-skill optional-deps (#43)

---

## v0.3.1 — 2026-06-15

### Fixes
- fix(release): chore/docs-only ranges yield none (revert #38 patch floor) (#42)

---

## v0.3.0 — 2026-06-11

### Features
- feat(review): teammate-voice comments, Comment block in chat output, drop afaict (#41)

---

## v0.2.3 — 2026-06-10

### Fixes
- fix(release): use first non-empty line as commit subject in parser (#40)

---

## v0.2.2 — 2026-06-10

### Fixes
- fix(release): honor skip-release marker only in subject/trailer, not prose (#39)

---

# Changelog

All notable changes to devflow. New entries are prepended automatically by the
release workflow (`.github/workflows/release.yml`).

## v0.2.1 — 2026-05-30

### Features
- `render-diagram` skill / `devflow visualizations render`: pure-node Excalidraw → PNG export (no browser, no MCP), shown inline via the Read tool; wired into review, spec-feature, codebase-walkthrough, update-visualizations, architecture-decision.

### Other Changes
- docs: record export-pipeline + release-pipeline gotchas (render-diagram maintenance notes + Release Process).

## v0.2.0 — 2026-05-30

### Features
- `/devflow:render-diagram` — author + render Excalidraw diagrams from a description or codebase analysis; embed in docs.
- visualizations: opt-in `format: mermaid|excalidraw` config.

### Fixes
- release pipeline: guard `check_version_consistency` badge grep under `pipefail`; create an annotated tag so `git push --follow-tags` pushes it.
