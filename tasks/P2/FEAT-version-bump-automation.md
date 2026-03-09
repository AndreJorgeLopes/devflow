---
id: FEAT-version-bump-automation
title: "Automate Version Badge Updates Across Commands on Release"
priority: P2
category: feature
status: open
depends_on: []
estimated_effort: S
files_to_touch:
  - Makefile
  - devflow-plugin/commands/*.md
---

# Automate Version Badge Updates Across Commands on Release

## Context

All command files in `devflow-plugin/commands/` include a `[devflow v0.1.0]` version badge in their `description` frontmatter. This badge is visible in Claude Code's `/` menu and helps identify the installed version.

Currently the version is hardcoded in each file. When releasing a new version, all 12+ command files need manual updates. The `VERSION` variable already exists in the Makefile (`VERSION := 0.1.0`).

## Desired Outcome

A `make version-bump` or `make release-prep` target that:

1. Reads `VERSION` from `Makefile`
2. Iterates all `devflow-plugin/commands/*.md` files
3. Updates the `[devflow v<old>]` badge to `[devflow v<new>]` in each description
4. Also updates `devflow-plugin/.claude-plugin/plugin.json` version field
5. Idempotent — safe to run multiple times

## Implementation

```makefile
version-bump: ## Update version badge in all command descriptions
	@echo "Updating version to $(VERSION)..."
	@for f in devflow-plugin/commands/*.md; do \
		sed -i '' 's/\[devflow v[0-9.]*\]/[devflow v$(VERSION)]/' "$$f"; \
	done
	@sed -i '' 's/"version": "[^"]*"/"version": "$(VERSION)"/' devflow-plugin/.claude-plugin/plugin.json
	@echo "Version updated to $(VERSION) in all command files and plugin.json"
```

Alternatively, integrate into the existing `release` target so version bump happens automatically before tarball creation.

## Acceptance Criteria

- [ ] `make version-bump` updates all command descriptions to match `VERSION`
- [ ] `plugin.json` version field is also updated
- [ ] Running twice with same version produces no diff
- [ ] New command files added to the folder are automatically picked up (glob, not hardcoded list)
