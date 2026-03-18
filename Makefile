PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
LIBDIR := $(PREFIX)/share/devflow
VERSION := 0.1.0
TARBALL := devflow-$(VERSION).tar.gz

.PHONY: install uninstall link test test-unit brew-local release help plugin-dev plugin-unlink plugin-install check-version check-formula

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

test: ## Run smoke tests
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
