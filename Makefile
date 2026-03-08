SHELL := /bin/bash

# Development targets
.PHONY: bootstrap test lint gen-lockfiles format help
.PHONY: docker-build docker-run docker-clean docker-push
.PHONY: dev-setup dev-clean dev-logs
.PHONY: deploy-rotation-check deploy-rotation-dry-run deploy-rotation deploy-rotation-verbose

# Default target
.DEFAULT_GOAL := help

# Color output
HELP_SPACING = 20

help: ## Display this help message
	@echo "Self-Hosted Runner Development - Available targets:"
	@echo ""
	@echo "Development Setup:"
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-$(HELP_SPACING)s %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make bootstrap        # Initialize dev environment"
	@echo "  make docker-build     # Build self-hosted runner image"
	@echo "  make docker-run       # Run self-hosted runner locally"
	@echo "  make test             # Run all tests"

bootstrap: ## Initialize development environment (install dependencies)
	@echo "Bootstrap: install repo-wide tools"
	if [ -f package.json ]; then npm ci || true; fi
	if [ -f requirements.txt ]; then pip3 install -r requirements.txt || true; fi
	@echo "✓ Bootstrap complete"

test: ## Run all repository tests
	@echo "Run repo tests (best-effort)"
	# Run workspace-level tests where available
	for d in $(shell find . -maxdepth 2 -type f -name package.json -printf '%h\n' | sort -u); do \
	  echo "--> $$d"; \
	  if [ -f "$$d/package.json" ]; then (cd $$d && npm test --silent) || true; fi; \
	done

lint: ## Run linting checks (ESLint, pre-commit, etc.)
	@echo "Run ESLint where configured"
	for d in $(shell find . -maxdepth 2 -type f -name package.json -printf '%h\n' | sort -u); do \
	  if [ -f "$$d/.eslintrc.js" ] || grep -q 'eslint' "$$d/package.json" 2>/dev/null; then \
	    echo "--> lint $$d"; (cd $$d && npx eslint .) || true; \
	  fi; \
	done

gen-lockfiles: ## Generate missing package-lock.json files (dry-run by default)
	@echo "Generate missing package-lock.json files (dry-run by default)"
	./scripts/gen-lockfiles.sh --dry-run || true

format: ## Format staged files (pre-commit)
	@echo "Format staged files (pre-commit runs formatting)"
	pre-commit run --all-files || true

# Docker targets
docker-build: ## Build self-hosted runner Docker image
	@echo "Building self-hosted runner image..."
	docker build -t kushin77/self-hosted-runner:latest \
		--build-arg RUNNER_VERSION=2.332.0 \
		--build-arg BUILD_DATE="$$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
		--build-arg BUILD_COMMIT_SHA="$$(git rev-parse HEAD 2>/dev/null || echo 'unknown')" \
		-f Dockerfile .
	@echo "✓ Docker image built: kushin77/self-hosted-runner:latest"

docker-run: ## Run self-hosted runner container locally
	@echo "Starting self-hosted runner container..."
	docker run --rm -it \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-e RUNNER_TOKEN="$${RUNNER_TOKEN:-test}" \
		-e RUNNER_URL="$${RUNNER_URL:-https://github.com/kushin77/self-hosted-runner}" \
		kushin77/self-hosted-runner:latest

docker-clean: ## Remove built docker images and containers
	@echo "Cleaning Docker resources..."
	docker rmi kushin77/self-hosted-runner:latest 2>/dev/null || true
	docker container prune --force 2>/dev/null || true
	@echo "✓ Docker cleanup complete"

docker-push: ## Push docker image to registry (requires auth)
	@echo "Pushing to Docker registry..."
	docker push kushin77/self-hosted-runner:latest || (echo "Push failed - ensure docker login credentials are set"; exit 1)
	@echo "✓ Docker image pushed"

# Development environment targets
dev-setup: bootstrap docker-build ## Set up complete development environment
	@echo "✓ Development environment ready"

dev-clean: docker-clean ## Clean up development environment
	@echo "✓ Development environment cleaned"

dev-logs: ## View logs from running containers
	@echo "Container logs (last 50 lines):"
	docker logs --tail=50 -f $$(docker ps -q) 2>/dev/null || echo "No running containers"

# Deployment targets
deploy-rotation-check: ## Validation check for staging deployment
	@echo "Deployment Check: validate staging playbook without applying changes"
	./scripts/deploy-rotation-staging.sh --check || true

deploy-rotation-dry-run: ## Dry-run deployment (no changes applied)
	@echo "Deployment Dry-Run: syntax-check and check mode (no apply)"
	./scripts/deploy-rotation-staging.sh --dry-run || true

deploy-rotation: ## Full deployment to staging environment
	@echo "Deploy Rotation Automation: full deployment to staging"
	./scripts/deploy-rotation-staging.sh

deploy-rotation-verbose: ## Deployment with verbose logging
	@echo "Deploy Rotation Automation: with verbose logging"
	./scripts/deploy-rotation-staging.sh --verbose
