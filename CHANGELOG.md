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
