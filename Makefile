check:
	@echo "Running repository checks..."
	@echo "No checks configured"

install-hooks:
	@echo "No pre-commit config present to install hooks"
check:
	@echo "Running repository checks..."
	@git diff --quiet --cached || true
	@bash scripts/ci/check_no_github_actions.sh
	@bash scripts/ci/scan_secrets.sh
	@echo "All checks passed"

install-hooks:
	@pre-commit install || true
SHELL:=/bin/bash
.PHONY: check install-hooks

check:
	@echo "Running repository checks..."
	@bash scripts/ci/check_no_github_actions.sh
	@bash scripts/ci/scan_secrets.sh
	@echo "All checks passed"

install-hooks:
	@command -v pre-commit >/dev/null 2>&1 || { echo "Install pre-commit: pip install pre-commit"; exit 1; }
	@pre-commit install
	@echo "pre-commit hooks installed"
