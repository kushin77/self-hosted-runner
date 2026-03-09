# Docker Configuration & Best Practices Guide

## Overview

This repository uses a multi-service containerized architecture with 9 Dockerfiles and 6 Docker Compose configurations for orchestrating observability, monitoring, and service deployment.

## Dockerfile Inventory

### Core Components

| Component | Location | Base Image | Purpose |
|-----------|----------|-----------|---------|
| **Self-Hosted Runner** | `Dockerfile` | `ubuntu:22.04` | GitHub Actions runner with Docker CLI & docker-compose |
| **Portal** | `apps/portal/Dockerfile` | `node:20-alpine` | Web UI for admin/user management |
| **Vault Shim** | `services/vault-shim/Dockerfile` | `node:18-alpine` | Secrets abstraction layer |
| **Managed Auth** | `services/managed-auth/Dockerfile` | `node:18-alpine` | OAuth + Vault token management |
| **Provisioner Worker** | `services/provisioner-worker/Dockerfile` | `node:18-alpine` | Terraform provisioning engine |
| **GitHub Runner** | `build/github-runner/Dockerfile` | `node:18-alpine` | Alternative runner variant |
| **Vault Automation** | `scripts/automation/pmo/Dockerfile.vault` | TBD | Vault-related PMO automation |
| **Backup/DR** | `Dockerfile.backup` | `python:3.14-alpine` | Disaster recovery backup image |

## Docker Build & Deployment

### Building Images

```bash
# Build main self-hosted runner image
make docker-build

# Build with specific runner version
docker build -t kushin77/self-hosted-runner:latest \
  --build-arg RUNNER_VERSION=2.333.0 \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --build-arg BUILD_COMMIT_SHA="$(git rev-parse HEAD)" \
  -f Dockerfile .

# Build specific service
docker build -t kushin77/vault-shim:latest services/vault-shim/

# Build with Docker Compose
docker-compose -f deploy/otel/docker-compose.yml build
```

### Running Containers

```bash
# Run self-hosted runner locally
make docker-run

# Run with environment variables
docker run --rm -it \
  -e RUNNER_TOKEN="${RUNNER_TOKEN}" \
  -e RUNNER_URL="https://github.com/kushin77/self-hosted-runner" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  kushin77/self-hosted-runner:latest

# Run all services via Docker Compose
docker-compose -f deploy/otel/docker-compose.yml up -d
```

## Security & Vulnerability Management

### Dependabot Configuration

Dependabot is configured in `.github/dependabot.yml` with:

- **npm** — Weekly updates (Mondays, 03:00)
- **docker** — Weekly updates (Mondays, 04:00)  
- **gomod** — Weekly updates (Mondays, 05:00)
- **github-actions** — Weekly updates (Mondays, 06:00)
- **terraform** — Weekly updates (Mondays, 08:00)

### Known Vulnerabilities & Remediation

**High/Critical Packages:**
- **tar** (5 alerts) — Transitive dependency via workflow actions
- **node-forge** (4 alerts) — Transitive dependency
- **minimatch** (3 alerts) — Transitive dependency
- **glob** (1 alert) — Transitive dependency

**Remediation PRs in Progress:**
- PR #1270 — Docker base: python 3.11 → 3.14-alpine
- PR #1179 — npm: esbuild 0.21.5 → 0.27.3
- PR #443 — Action: actions/checkout 4 → 6

**Base Image Security:**
- Main runner uses `ubuntu:22.04` (actively maintained)
- Service containers use `node:18-alpine` (minimal, hardened)
- Backup uses `python:3.14-alpine` (minimal, latest)

### Security Scanning

```bash
# View Dependabot alerts
gh issue list --repo kushin77/self-hosted-runner --label security --state open

# Check active Dependabot PRs
gh pr list --author dependabot[bot] --state open --repo kushin77/self-hosted-runner

# Run local security audit (if available)
npm audit
docker scan kushin77/self-hosted-runner:latest
```

## Docker Compose Configurations

### Available Stacks

| Stack | File | Components | Purpose |
|-------|------|-----------|---------|
| OTEL | `deploy/otel/docker-compose.yml` | OTEL Collector, exporters | Observability |
| Observability | `scripts/automation/pmo/prometheus/docker-compose-observability.yml` | Prometheus, Grafana, AlertManager | Metrics & alerts |
| PMO Automation | `scripts/automation/pmo/docker-compose.yml` | Vault, Redis, provisioner | Policy & operations |
| Provisioner | `services/provisioner-worker/deploy/docker-compose.yml` | Worker, dependencies | Provisioning engine |
| Monitoring | `deploy/monitoring/docker-compose.yml` | Metrics, dashboards | Central monitoring |

### Starting Observability Stack

```bash
docker-compose -f deploy/otel/docker-compose.yml up -d
docker-compose -f scripts/automation/pmo/prometheus/docker-compose-observability.yml up -d
```

## Image Publishing & Registry

### CI/CD Workflows

- **artifact-registry-automation.yml** — Automates builds to GCP Artifact Registry
- **publish-portal-image.yml** — Publishes portal image to registry
- **docker-hub-weekly-dr-testing.yml** — Weekly DR testing with Docker Hub

### Publishing Images

```bash
# Push to registry (requires auth)
make docker-push

# Tag image before pushing
docker tag kushin77/self-hosted-runner:latest \
  gcr.io/my-project/self-hosted-runner:latest

docker push gcr.io/my-project/self-hosted-runner:latest
```

## .dockerignore Best Practices

All Docker contexts now include `.dockerignore` files to:
- **Reduce build context size** (faster builds)
- **Exclude sensitive files** (.env, .git, credentials)
- **Avoid test/doc inclusion** (smaller images)

Root-level `.dockerignore` excludes:
- Git files (.git, .github, .gitignore)
- Development directories (node_modules, __pycache__)
- CI/CD workflows
- Documentation & examples
- Testing & coverage files
- Temporary files & logs

## Dockerfile Best Practices

### ✅ Implemented

1. **Multi-stage builds** (where applicable) — Reduces final image size
2. **Layer caching optimization** — Dependencies pinned, immutable
3. **Non-root execution** — `runner` user in main containers
4. **Health checks** — Verify container functionality
5. **Minimal base images** — Alpine for services, ubuntu:22.04 for runner
6. **Clean artifact layers** — `rm -rf /var/lib/apt/lists/*`
7. **Immutable metadata** — Build date, commit SHA in labels

### 🔧 Remaining Work

1. **Multi-stage builds** for services — Can separate build/runtime
2. **CVE scanning in CI/CD** — Automated trivy/snyk integration
3. **Image signing** — Cosign/notation for supply chain security
4. **Registry scanning** — Enable registry native scanning

## Troubleshooting

### Docker Build Issues

```bash
# Clear Docker build cache
docker builder prune -a

# Rebuild without cache
docker build --no-cache -t kushin77/self-hosted-runner:latest .

# Check build layers
docker history kushin77/self-hosted-runner:latest
```

### Container Runtime Issues

```bash
# View container logs
docker logs <container_id>

# Inspect container
docker inspect <container_id>

# Access container shell (if exec available)
docker exec -it <container_id> /bin/bash
```

### Docker Compose Issues

```bash
# Check service status
docker-compose ps

# View service logs
docker-compose logs -f <service>

# Rebuild services
docker-compose down
docker-compose up -d --build
```

## References

- **[Dependabot Configuration](.github/dependabot.yml)** — Automated updates setup
- **[Main Dockerfile](../../Dockerfile)** — Self-hosted runner image spec
- **[Development Setup](../../Makefile)** — `make docker-build`, `make docker-run`
- **[Security Automation](../archive/completion-reports/SECURITY_AUTOMATION_DEPLOYMENT_FINAL.md)** — Vulnerability tracking
- **.dockerignore files** — Build optimization across all services
