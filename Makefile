SHELL := /bin/bash

.PHONY: bootstrap test lint gen-lockfiles format

bootstrap:
	@echo "Bootstrap: install repo-wide tools"
	if [ -f package.json ]; then npm ci || true; fi

test:
	@echo "Run repo tests (best-effort)"
	# Run workspace-level tests where available
	for d in $(shell find . -maxdepth 2 -type f -name package.json -printf '%h\n' | sort -u); do \
	  echo "--> $${d}"; \
	  if [ -f "$${d}/package.json" ]; then (cd $${d} && npm test --silent) || true; fi; \
	done

lint:
	@echo "Run ESLint where configured"
	for d in $(shell find . -maxdepth 2 -type f -name package.json -printf '%h\n' | sort -u); do \
	  if [ -f "$${d}/.eslintrc.js" ] || grep -q 'eslint' "$${d}/package.json" 2>/dev/null; then \
	    echo "--> lint $${d}"; (cd $${d} && npx eslint .) || true; \
	  fi; \
	done

gen-lockfiles:
	@echo "Generate missing package-lock.json files (dry-run by default)"
	./scripts/gen-lockfiles.sh --dry-run

format:
	@echo "Format staged files (pre-commit runs formatting)"
	pre-commit run --all-files || true
