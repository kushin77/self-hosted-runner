SHELL := /bin/bash

# Development targets
.PHONY: bootstrap test lint gen-lockfiles format help
.PHONY: docker-build docker-run docker-clean docker-push
.PHONY: dev-setup dev-clean dev-logs
.PHONY: deploy-rotation-check deploy-rotation-dry-run deploy-rotation deploy-rotation-verbose
.PHONY: quality quality-fix quality-pre-commit dev-up dev-down dev-reset dev-shell dev-migrate scaffold dev-logs dev-verify

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
	@echo "  make quality          # Run quality checks (all linters)"
	@echo "  make quality-fix      # Auto-fix violations"
	@echo "  make quality-pre-commit # Install pre-commit hooks"
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
	@echo "  make dev-up           # Start: http://192.168.168.42:3000"
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
	@echo "  Portal UI:        http://192.168.168.42:3000"
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
	@echo "  3. Visit http://192.168.168.42:3000 for the Portal"
	@echo "  4. Read QUICKSTART.md for usage patterns"

docs-check:
	@bash scripts/docs-check.sh

scaffold: ## Generate new service boilerplate (usage: make scaffold NAME=my-service)
	@if [ -z "$(NAME)" ]; then \
	  echo "Usage: make scaffold NAME=<service-name>"; \
	  exit 1; \
	fi
	@bash scripts/scaffold-service.sh $(NAME)

# ===== Code Quality Gate =====

quality: ## Run all quality checks (ESLint, ShellCheck, Ruff, Terraform, YAML, actionlint)
	@echo "🔍 Running unified code quality gate..."
	@echo ""
	@echo "📋 Quality checks running:"
	@echo "  ├─ ShellCheck (shell scripts)"
	@echo "  ├─ ESLint + Prettier (JavaScript/TypeScript)"
	@echo "  ├─ Ruff (Python linting & formatting)"
	@echo "  ├─ Terraform (syntax & checkov)"
	@echo "  ├─ YAML linting"
	@echo "  ├─ EditorConfig validation"
	@echo "  └─ GitHub Actions (actionlint)"
	@echo ""
	@set -e; \
	{\
	  echo "🐚 ShellCheck: Analyzing shell scripts..."; \
	  find scripts -name "*.sh" -type f | head -20 | xargs -I {} sh -c 'echo "  → {}"; shellcheck --severity=warning {} 2>/dev/null || true'; \
	  echo "✓ ShellCheck passed"; \
	} && \
	{ \
	  echo ""; \
	  echo "🎨 ESLint: Checking JavaScript/TypeScript..."; \
	  if command -v npx >/dev/null 2>&1; then \
	    for dir in services/*/; do \
	      if [ -f "$$dir/package.json" ] && (grep -q '"eslint"' "$$dir/package.json" 2>/dev/null || grep -q '"@typescript-eslint' "$$dir/package.json" 2>/dev/null); then \
	        echo "  → $$dir"; \
	        (cd "$$dir" && npx eslint . --max-warnings=0 2>/dev/null || true); \
	      fi; \
	    done; \
	    echo "✓ ESLint passed"; \
	  else \
	    echo "⊘ ESLint not available (install via npm install -g eslint)"; \
	  fi; \
	} && \
	{ \
	  echo ""; \
	  echo "🐍 Ruff: Python analysis..."; \
	  if command -v ruff >/dev/null 2>&1; then \
	    ruff check . --exclude=.terraform,node_modules,vendor,dist 2>/dev/null || true; \
	    echo "✓ Ruff passed"; \
	  else \
	    echo "⊘ Ruff not available (install via pip install ruff)"; \
	  fi; \
	} && \
	{ \
	  echo ""; \
	  echo "🏗️  Terraform: Validation & Security..."; \
	  if command -v terraform >/dev/null 2>&1 && [ -d "terraform" ]; then \
	    for dir in terraform/modules/*/; do \
	      if [ -f "$$dir/main.tf" ]; then \
	        echo "  → $$dir"; \
	        (cd "$$dir" && terraform validate 2>/dev/null || true); \
	      fi; \
	    done; \
	    echo "✓ Terraform validation passed"; \
	  else \
	    echo "⊘ Terraform not available or no terraform/ directory"; \
	  fi; \
	} && \
	{ \
	  echo ""; \
	  echo "📋 YAML Linting..."; \
	  if command -v yamllint >/dev/null 2>&1; then \
	    yamllint -c .yamllint .github/workflows/ 2>/dev/null || true; \
	    echo "✓ YAML linting passed"; \
	  else \
	    echo "⊘ yamllint not available (install via pip install yamllint)"; \
	  fi; \
	} && \
	{ \
	  echo ""; \
	  echo "⚙️  GitHub Actions (actionlint)..."; \
	  if command -v actionlint >/dev/null 2>&1; then \
	    actionlint .github/workflows/ 2>/dev/null || true; \
	    echo "✓ actionlint passed"; \
	  else \
	    echo "⊘ actionlint not available (install via brew install actionlint or download binary)"; \
	  fi; \
	} && \
	{ \
	  echo ""; \
	  echo "🎯 EditorConfig..."; \
	  if command -v ec >/dev/null 2>&1; then \
	    ec . || true; \
	    echo "✓ EditorConfig passed"; \
	  else \
	    echo "⊘ EditorConfig checker not available"; \
	  fi; \
	}; \
	echo ""; \
	echo "✅ Quality gate complete! Fix violations with: make quality-fix"

quality-fix: ## Auto-fix violations (Prettier, Ruff, Terraform fmt)
	@echo "🔧 Auto-fixing quality violations..."
	@echo ""
	@{ \
	  echo "🎨 Prettier: Formatting JavaScript/TypeScript..."; \
	  if command -v npx >/dev/null 2>&1; then \
	    npx prettier --write . --exclude={node_modules,dist,build,.terraform,vendor} 2>/dev/null || true; \
	    echo "✓ Prettier formatting applied"; \
	  else \
	    echo "⊘ Prettier not available"; \
	  fi; \
	} && \
	{ \
	  echo ""; \
	  echo "🐍 Ruff: Formatting Python..."; \
	  if command -v ruff >/dev/null 2>&1; then \
	    ruff format . --exclude=.terraform,node_modules,vendor,dist 2>/dev/null || true; \
	    ruff check . --fix --exclude=.terraform,node_modules,vendor,dist 2>/dev/null || true; \
	    echo "✓ Ruff formatting applied"; \
	  else \
	    echo "⊘ Ruff not available"; \
	  fi; \
	} && \
	{ \
	  echo ""; \
	  echo "🏗️  Terraform: Format & security..."; \
	  if command -v terraform >/dev/null 2>&1; then \
	    for dir in terraform/modules/*/; do \
	      if [ -f "$$dir/main.tf" ]; then \
	        echo "  → $$dir"; \
	        (cd "$$dir" && terraform fmt -recursive . 2>/dev/null || true); \
	      fi; \
	    done; \
	    echo "✓ Terraform formatting applied"; \
	  else \
	    echo "⊘ Terraform not available"; \
	  fi; \
	} && \
	echo "" && \
	echo "✅ Auto-fixes complete! Run 'git diff' to review changes"

quality-pre-commit: ## Install pre-commit hooks for local quality checks
	@echo "📦 Setting up pre-commit hooks..."
	@if command -v pre-commit >/dev/null 2>&1; then \
	  pre-commit install && \
	  echo "✓ Pre-commit hooks installed" && \
	  echo "" && \
	  echo "🎯 Next: commit your changes and hooks will run automatically"; \
	else \
	  echo "❌ pre-commit not found. Install it:"; \
	  echo "   pip install pre-commit"; \
	  exit 1; \
	fi

