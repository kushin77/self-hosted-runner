SHELL := /bin/bash

# Development targets
.PHONY: bootstrap test lint gen-lockfiles format help
.PHONY: docker-build docker-run docker-clean docker-push
.PHONY: dev-setup dev-clean dev-logs
.PHONY: deploy-rotation-check deploy-rotation-dry-run deploy-rotation deploy-rotation-verbose
.PHONY: quality quality-fix quality-pre-commit

# Default target
.DEFAULT_GOAL := help

# Color output
HELP_SPACING = 20

help: ## Display this help message
	@echo "Self-Hosted Runner Development - Available targets:"
	@echo ""
	@echo "📚 Local Development Stack (Docker Compose):"
	@echo "  make dev-up           # Start full local stack"
	@echo "  make dev-down         # Stop local stack"
	@echo "  make dev-reset        # Reset stack (delete volumes)"
	@echo "  make dev-logs         # View live logs"
	@echo "  make dev-verify       # Run smoke tests"
	@echo "  make dev-shell        # Drop into service container"
	@echo ""
	@echo "⚙️  Standard Development:"
	@echo "  make bootstrap        # Install all dependencies"
	@echo "  make test             # Run all tests"
	@echo "  make quality          # Run quality checks"
	@echo ""
	@echo "🐳 Docker & Deployment:"
	@echo "  make docker-build     # Build runner image"
	@echo "  make docker-push      # Push to registry"
	@echo "  make deploy-rotation  # Deploy to staging"
	@echo ""
	@echo "📋 All targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-$(HELP_SPACING)s %s\n", $$1, $$2}'
	@echo ""
	@echo "💡 Examples:"
	@echo "  make dev-up           # Start: http://localhost:3000"
	@echo "  make dev-logs         # See what's happening"
	@echo "  make dev-verify       # Verify services are healthy"
	@echo "  make dev-shell SERVICE=vault  # SSH into container"

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

# ===== DX Accelerator: Local Development Stack =====

dev-up: ## Start full local development stack (docker-compose)
	@echo "🚀 Starting local development stack..."
	@echo "  Services: Vault, Redis, Postgres, MinIO, Prometheus, Grafana"
	@echo "  Apps: Portal, Provisioner, VaultShim, AI-Oracle, ManagedAuth, PipelineRepair"
	docker-compose -f docker-compose.dev.yml up -d
	@echo ""
	@echo "✓ Stack started. Waiting for services to be ready..."
	@sleep 5
	@echo ""
	@echo "🌐 Services available at:"
	@echo "  Portal UI:        http://localhost:3000"
	@echo "  Provisioner API:  http://localhost:8000/health"
	@echo "  VaultShim:        http://localhost:8080"
	@echo "  Vault UI:         http://localhost:8200/ui"
	@echo "  Prometheus:       http://localhost:9090"
	@echo "  Grafana:          http://localhost:3001 (admin/admin)"
	@echo "  MinIO:            http://localhost:9001 (minioadmin/minioadmin123)"
	@echo ""
	@echo "Run 'make dev-logs' to view logs"
	@echo "Run 'make dev-down' to stop the stack"

dev-down: ## Stop local development stack
	@echo "🛑 Stopping local development stack..."
	docker-compose -f docker-compose.dev.yml down
	@echo "✓ Stack stopped"

dev-reset: ## Reset dev stack (removes volumes, caches, rebuilds)
	@echo "🔄 Resetting development environment (WARNING: loses local data)"
	@read -p "Press Enter to continue or Ctrl+C to cancel..."
	docker-compose -f docker-compose.dev.yml down -v
	docker-compose -f docker-compose.dev.yml build --no-cache
	@echo "✓ Reset complete. Run 'make dev-up' to restart"

dev-logs: ## View live logs from all dev services
	@echo "📊 Streaming logs from development stack..."
	@echo "(Press Ctrl+C to exit)"
	docker-compose -f docker-compose.dev.yml logs -f --tail=50

dev-logs-service: ## View logs from specific service (usage: make dev-logs-service SERVICE=vault)
	@if [ -z "$(SERVICE)" ]; then \
	  echo "Usage: make dev-logs-service SERVICE=<service-name>"; \
	  echo "Available services:"; \
	  grep "container_name:" docker-compose.dev.yml | sed 's/.*: //'; \
	else \
	  docker-compose -f docker-compose.dev.yml logs -f $(SERVICE); \
	fi

dev-shell: ## Drop into a running service container (usage: make dev-shell SERVICE=vault)
	@if [ -z "$(SERVICE)" ]; then \
	  echo "Usage: make dev-shell SERVICE=<service-name>"; \
	  echo "Available services:"; \
	  docker-compose -f docker-compose.dev.yml ps --services; \
	else \
	  docker-compose -f docker-compose.dev.yml exec $(SERVICE) bash || docker-compose -f docker-compose.dev.yml exec $(SERVICE) sh; \
	fi

dev-status: ##Show status of all dev services
	@echo "📋 Development stack status:"
	docker-compose -f docker-compose.dev.yml ps

dev-verify: ## Run smoke tests on local stack
	@echo "🧪 Running smoke tests on local development stack..."
	@echo "  Checking Vault..."
	@curl -s http://localhost:8200/v1/sys/health | jq '.' || echo "❌ Vault not responding"
	@echo ""
	@echo "  Checking Provisioner..."
	@curl -s http://localhost:8000/health | jq '.' || echo "❌ Provisioner not responding"
	@echo ""
	@echo "  Checking Prometheus..."
	@curl -s http://localhost:9090/-/healthy | head -1 || echo "❌ Prometheus not responding"
	@echo ""
	@echo "✓ Smoke tests complete"

dev-migrate: ## Run any pending database migrations
	@echo "🗄️  Running database migrations..."
	@if [ -f scripts/run-migrations.sh ]; then \
	  bash scripts/run-migrations.sh; \
	else \
	  echo "⊘ No migration script found at scripts/run-migrations.sh"; \
	fi

dev-setup-complete: bootstrap docker-build dev-up ## Complete dev setup: bootstrap, build, and start stack
	@echo "✅ Development environment fully set up and running!"
	@echo "📚 Next steps:"
	@echo "  1. Run 'make dev-verify' to check services"
	@echo "  2. Run 'make dev-logs' to see service logs"
	@echo "  3. Visit http://localhost:3000 for the Portal"
	@echo "  4. Read QUICKSTART.md for usage patterns"

docs-check:
	@bash scripts/docs-check.sh

# Developer experience targets
dev-up:
	@echo "Starting local development stack (docker-compose.dev.yml)"
	@docker-compose -f docker-compose.dev.yml up -d --build

dev-down:
	@echo "Tearing down local development stack"
	@docker-compose -f docker-compose.dev.yml down

dev-reset:
	@echo "Resetting local development stack (removes volumes)"
	@docker-compose -f docker-compose.dev.yml down -v --remove-orphans

dev-shell:
	@sh -c 'if [ -z "$$1" ]; then echo "Usage: make dev-shell SERVICE="; exit 2; fi; docker-compose -f docker-compose.dev.yml exec $$1 /bin/sh'

dev-migrate:
	@echo "Running migrations (service: provisioner-worker)"
	@docker-compose -f docker-compose.dev.yml exec provisioner-worker /bin/sh -c "./scripts/migrate.sh || true"

scaffold:
	@sh scripts/scaffold-service.sh $(NAME)

dev-logs:
	@docker-compose -f docker-compose.dev.yml logs -f --tail=200

dev-verify:
	@echo "Running smoke checks against core endpoints"
	@echo "Checking Vault..."
	@docker-compose -f docker-compose.dev.yml exec -T vault sh -c 'curl -sSf localhost:8200/v1/sys/health >/dev/null && echo OK || echo FAIL'

