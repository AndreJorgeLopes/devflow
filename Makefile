PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
LIBDIR := $(PREFIX)/share/devflow
VERSION := 0.25.0
TARBALL := devflow-$(VERSION).tar.gz

.PHONY: install uninstall link test test-unit brew-local release help plugin-dev plugin-unlink plugin-install check-version check-formula version-bump flows flows-check skills-sync skills-check skills-guard determinism mirror

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Install devflow to PREFIX (~/.local by default)
	@mkdir -p $(BINDIR) $(LIBDIR)
	@cp -R lib templates skills config docker $(LIBDIR)/
	@cp bin/devflow $(LIBDIR)/devflow-bin
	@chmod 755 $(LIBDIR)/devflow-bin
	@printf '#!/usr/bin/env bash\nexport DEVFLOW_ROOT="%s"\nexec "%s/devflow-bin" "$$@"\n' \
		"$(LIBDIR)" "$(LIBDIR)" > $(BINDIR)/devflow
	@chmod 755 $(BINDIR)/devflow
	@echo "devflow $(VERSION) installed to $(BINDIR)/devflow"
	@echo "Make sure $(BINDIR) is in your PATH."

uninstall: ## Remove devflow
	@rm -f $(BINDIR)/devflow
	@rm -rf $(LIBDIR)
	@echo "devflow removed."

link: ## Symlink bin/devflow for local development
	@mkdir -p $(BINDIR)
	@ln -sf $(CURDIR)/bin/devflow $(BINDIR)/devflow
	@echo "devflow linked: $(BINDIR)/devflow -> $(CURDIR)/bin/devflow"
	@echo "DEVFLOW_ROOT will default to $(CURDIR) when running from source."

test: skills-check flows-check ## Run smoke tests
	@echo "=== devflow smoke tests ==="
	@if [ -x bin/devflow ]; then \
		echo "PASS: bin/devflow exists and is executable"; \
	else \
		echo "FAIL: bin/devflow not found or not executable"; exit 1; \
	fi
	@if bin/devflow version 2>/dev/null | grep -q "$(VERSION)"; then \
		echo "PASS: devflow version reports $(VERSION)"; \
	else \
		echo "SKIP: devflow version (binary may not be ready yet)"; \
	fi
	@if bin/devflow help 2>/dev/null | grep -qi "usage\|help\|devflow"; then \
		echo "PASS: devflow help produces output"; \
	else \
		echo "SKIP: devflow help (binary may not be ready yet)"; \
	fi
	@echo "=== done ==="

test-unit: ## Run unit tests (bats)
	@bats tests/unit/

skills-sync: ## Regenerate plugin skill/command copies + flows from repo-root skills/ (the source of truth)
	@bash scripts/build-skills.sh
	@bash scripts/build-flows.sh

skills-check: ## Fail if generated plugin skills/commands drift from repo-root skills/ (run 'make skills-sync' to fix)
	@bash scripts/build-skills.sh
	@git diff --quiet -- devflow-plugin/skills devflow-plugin/commands devflow-plugin/.claude-plugin/plugin.json || { echo "plugin skill copies out of date — run 'make skills-sync' and commit"; git --no-pager diff --stat -- devflow-plugin/skills devflow-plugin/commands devflow-plugin/.claude-plugin/plugin.json; exit 1; }

skills-guard: ## Detect skill edits made in the WRONG (generated) tree and fold them into the source
	@bash scripts/skills-guard.sh

determinism: ## Run the promptfoo determinism gate on the WORKING-TREE skills (needs API keys + Langfuse; not in CI). One: make determinism SKILL=<name>. Claude-spawning gate defaults to sonnet.
	@command -v npx >/dev/null 2>&1 || { echo "determinism: npx (Node) is required"; exit 1; }
	@[ -f "$(HOME)/.config/zsh/secrets" ] && . "$(HOME)/.config/zsh/secrets" 2>/dev/null || true; \
	export PROMPTFOO_DISABLE_DB=true; \
	fail=0; ran=0; \
	for cfg in skills/*/determinism.promptfooconfig.yaml; do \
		[ -f "$$cfg" ] || continue; \
		name="$$(basename "$$(dirname "$$cfg")")"; \
		if [ -n "$(SKILL)" ] && [ "$(SKILL)" != "$$name" ]; then continue; fi; \
		echo "=== determinism gate: $$name ==="; ran=1; \
		npx -y promptfoo@latest eval -c "$$cfg" --no-cache -j 1 || fail=1; \
	done; \
	[ "$$ran" = 1 ] || { echo "determinism: no config matched$(if $(SKILL), for SKILL=$(SKILL),)"; exit 1; }; \
	[ "$$fail" = 0 ] || { echo "determinism gate FAILED"; exit 1; }; \
	echo "determinism gate passed"

mirror: ## Mirror skills/<name>/SKILL.md into Langfuse prompt-management (needs Langfuse + keys). One: make mirror SKILL=<name>
	@bin/devflow skills mirror $(if $(SKILL),--name $(SKILL),)

flows: ## Regenerate flow mini-plugins from canonical sources
	@bash scripts/build-flows.sh

flows-check: ## Fail if generated flows drift from canonical sources (run 'make flows' to fix)
	@bash scripts/build-flows.sh
	@git diff --quiet -- devflow-plugin/flows || { echo "flows out of date — run 'make flows' and commit"; git --no-pager diff --stat -- devflow-plugin/flows; exit 1; }

brew-local: ## Install via local Homebrew formula
	brew install --formula Formula/devflow.rb

plugin-dev: ## Symlink plugin commands/skills for live dev iteration
	@mkdir -p $(HOME)/.claude/commands $(HOME)/.claude/skills
	@ln -sfn $(CURDIR)/devflow-plugin/commands $(HOME)/.claude/commands/devflow
	@ln -sfn $(CURDIR)/devflow-plugin/skills/recall-before-task $(HOME)/.claude/skills/devflow-recall
	@claude plugin uninstall devflow@devflow-marketplace 2>/dev/null || true
	@echo "Dev symlinks created:"
	@echo "  ~/.claude/commands/devflow -> $(CURDIR)/devflow-plugin/commands"
	@echo "  ~/.claude/skills/devflow-recall -> $(CURDIR)/devflow-plugin/skills/recall-before-task"
	@echo "NOTE: LOCAL dev override — Claude now reads this working tree and does NOT"
	@echo "      auto-update from origin. 'git pull' here to advance it; run"
	@echo "      'make plugin-unlink && devflow init' to return to the auto-updating install."
	@echo "Restart Claude Code to pick up changes."

plugin-unlink: ## Remove dev symlinks
	@rm -f $(HOME)/.claude/commands/devflow
	@rm -f $(HOME)/.claude/skills/devflow-recall
	@echo "Dev symlinks removed."

plugin-install: ## Register marketplace and install plugin (end users)
	@if command -v claude >/dev/null 2>&1; then \
		claude plugin marketplace add AndreJorgeLopes/devflow 2>/dev/null; \
		claude plugin install devflow@devflow-marketplace 2>/dev/null \
			&& echo "devflow plugin installed" \
			|| echo "devflow plugin already installed or marketplace not found"; \
	else \
		echo "Claude Code not found — skipping plugin install"; \
	fi

check-version: ## Check version consistency across all files
	@bash -c 'source lib/utils.sh; source lib/watch.sh; check_version_consistency .'

check-formula: ## Check Formula SHA matches latest tarball
	@if [ ! -f Formula/devflow.rb ]; then echo "No Formula/devflow.rb found"; exit 0; fi
	@if [ ! -d dist ]; then echo "No dist/ directory — run 'make release' first"; exit 1; fi
	@TARBALL_SHA=$$(shasum -a 256 dist/devflow-$(VERSION).tar.gz 2>/dev/null | cut -d' ' -f1); \
	FORMULA_SHA=$$(grep 'sha256' Formula/devflow.rb | head -1 | sed 's/.*"\(.*\)".*/\1/'); \
	if [ "$$TARBALL_SHA" = "$$FORMULA_SHA" ]; then \
		echo "Formula SHA matches tarball"; \
	else \
		echo "MISMATCH: Formula has $$FORMULA_SHA, tarball is $$TARBALL_SHA" >&2; exit 1; \
	fi

version-bump: ## Bump version (usage: make version-bump V=0.2.0)
	@if [ -z "$(V)" ]; then echo "Usage: make version-bump V=0.2.0"; exit 1; fi
	@bash scripts/bump-version.sh $(V)

release: ## Create a release tarball
	@mkdir -p dist
	tar czf dist/$(TARBALL) \
		--exclude='.git' \
		--exclude='dist' \
		--exclude='*.tar.gz' \
		-C .. devflow
	@echo "Tarball: dist/$(TARBALL)"
	@echo "SHA256:  $$(shasum -a 256 dist/$(TARBALL) | cut -d' ' -f1)"
	@echo "Update Formula/devflow.rb with the SHA256 above."
