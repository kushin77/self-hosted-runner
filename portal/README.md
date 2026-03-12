# NexusShield Control Plane Portal

**Sovereign, Cloud-Agnostic, Enterprise OPS Platform**

## Overview

The NexusShield Portal is a comprehensive SaaS-ready operations control plane for managing infrastructure, deployments, secrets, and observability across multiple clouds in a sovereign, self-hosted manner.

### 🎯 Vision
- **Unrecognizable GitLab UI** - Fully customized ops-first experience
- **AI-Powered Troubleshooting** - Draw.io diagrams for failure analysis
- **Full Repo Integration** - All scripts, tools, tests accessible via Portal
- **Multi-Product Framework** - OPS (active), Security/CISO suite (future)
- **SaaS Architecture** - Production-grade, cloud-agnostic, self-hosted

## Architecture

### Monorepo Structure

```
portal/
├── packages/
│   ├── core/              # Shared services, types, utilities
│   ├── api/               # Express backend API
│   ├── diagram-engine/    # Draw.io integration & troubleshooting
│   ├── products/
│   │   ├── ops/           # OPS product (core)
│   │   └── security/      # Security suite (future)
│   └── frontend/          # React UI
├── scripts/               # Portal automation scripts
├── tests/                 # Testing infrastructure
├── docker/                # Containerization
├── ci/                    # CI/CD pipelines
└── docs/                  # Documentation
```

## Quick Start

### Prerequisites
- Node.js ≥18.0.0
- pnpm ≥8.0.0
- Docker (for containerization)

### Installation

```bash
cd portal
pnpm install
```

### Development

```bash
# Start all packages in dev mode (API + Frontend)
pnpm dev

# Start specific package
pnpm -C packages/api dev
pnpm -C packages/frontend dev
```

### Build

```bash
# Build all packages
pnpm build

# Production build
pnpm build:prod
```

### Testing

```bash
# Run all tests
pnpm test

# With coverage
pnpm test:cov

# Lint
pnpm lint

# Format
pnpm format
```

## Packages

### `@nexus/core`
Shared types, services, and utilities:
- Event system
- Logger
- Type definitions
- Common interfaces

### `@nexus/api`
Express backend serving REST API:
- Port: 5000
- GraphQL ready
- WebSocket support
- Service integrations

### `@nexus/diagram-engine`
Draw.io integration for troubleshooting:
- Diagram generation from logs
- Failure inference
- Actionable recommendations
- Architecture visualization

### `@nexus/products/ops`
Core OPS product suite:
- Deployment management
- Secrets management
- Observability dashboard
- Infrastructure views

### `@nexus/products/security`
Future security product:
- SAST/DAST scanning
- Compliance management
- Vulnerability tracking

### `@nexus/frontend`
React web interface:
- Port: 3000
- Responsive design
- Real-time updates
- Dark mode first

## API Documentation

### Health Check

```bash
curl http://localhost:5000/health
```

### Products

```bash
# List available products
GET /api/v1/products

# OPS product endpoints
GET /api/v1/ops/deployments
GET /api/v1/ops/secrets
GET /api/v1/ops/observability

# Diagram endpoints
POST /api/v1/diagrams/generate
GET /api/v1/diagrams/:id
```

## Integration with Repo

The Portal integrates all existing repo tools:

```
scripts/deploy/*          → /api/v1/ops/deployment/*
scripts/monitoring/*      → /api/v1/ops/observability/*
scripts/security/*        → /api/v1/security/*
scripts/ops/*             → /api/v1/ops/*
terraform/                → /api/v1/infrastructure/*
```

## Docker

### Build

```bash
pnpm docker:build
```

### Run

```bash
pnpm docker:run
# OR
docker run -p 3000:3000 -p 5000:5000 nexusshield/portal:latest
```

## Environment Variables

### API (.env)
```
NODE_ENV=development
PORT=5000
LOG_LEVEL=debug
API_URL=http://localhost:5000

# Cloud integrations
GCP_PROJECT_ID=your-project
AWS_REGION=us-east-1
VAULT_ADDR=http://localhost:8200
```

### Frontend (.env)
```
VITE_API_URL=http://localhost:5000
VITE_LOG_LEVEL=debug
```

## Deployment

### Local Development
```bash
pnpm portal:dev
```

### Docker Compose (Coming Soon)
```bash
docker-compose -f docker-compose.yml up
```

### Kubernetes (Coming Soon)
```bash
kubectl apply -f k8s/
```

## Contributing

1. Create feature branch: `git checkout -b feat/my-feature`
2. Make changes in appropriate package
3. Run tests: `pnpm test`
4. Format code: `pnpm format`
5. Commit: `git commit -am 'feat: add my feature'`
6. Open PR to main

## Testing

- Unit: `vitest`
- Integration: `vitest --run`
- E2E: `cypress`
- API: REST client tests

## Documentation

- [API Documentation](./docs/API.md)
- [Architecture](./docs/ARCHITECTURE.md)
- [Diagram Engine Guide](./docs/DIAGRAM_ENGINE.md)
- [OPS Product Guide](./docs/OPS_GUIDE.md)
- [Deployment Guide](./docs/DEPLOYMENT.md)

## Security

- All secrets via Vault/GSM/KMS (no hardcoding)
- RBAC for all operations
- Immutable audit trail
- TLS in-transit, KMS at-rest
- SOC2/HIPAA/GDPR ready

## Roadmap

### Phase 1 (Complete)
- ✅ Portal monorepo setup
- ✅ Core API framework
- ✅ Basic OPS product

### Phase 2 (In Progress)
- Diagram troubleshooting
- Full repo integration
- Test suite

### Phase 3 (Future)
- Security product
- CISO suite
- Advanced analytics

### Phase 4 (Future)
- Multi-tenancy
- Advanced scaling
- AI/ML features

## Support

- Issues: GitHub Issues
- Docs: See `docs/` folder
- Contributing: See `CONTRIBUTING.md`

## License

ISC

## Authors

- Lead Engineer (Autonomous)
- NexusShield Team

---

**Status:** MVP Phase (March 12, 2026)  
**Last Updated:** 2026-03-12
