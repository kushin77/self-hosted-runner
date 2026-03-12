# NexusShield Portal Architecture

**Document:** Architecture Overview  
**Date:** March 12, 2026  
**Version:** 1.0

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        User Interface Layer                          │
│                    (React Frontend, Web-Based)                       │
│       [Dashboard] [Deployments] [Secrets] [Observability] [Diagrams] │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                      HTTP/WebSocket
                             │
┌────────────────────────────┴────────────────────────────────────────┐
│                      API Gateway Layer                               │
│              (Express.js, TypeScript, Port 5000)                     │
│  [Routing] [Auth] [CORS] [Rate Limiting] [Logging] [Error Handling] │
└────────────────────────────┬────────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
   ┌─────────┐          ┌──────────┐        ┌─────────────────┐
   │   OPS   │          │ Diagram  │        │ Security/CISO   │
   │ Product │          │  Engine  │        │  Product (TBD)  │
   └─────────┘          └──────────┘        └─────────────────┘
        │                    │                    │
   [Services]           [Analysis]            [Services]
        │                    │                    │
        ├─────────────┬──────┴────────┬──────────┤
        │             │               │          │
        ▼             ▼               ▼          ▼
   [Deployment]  [Architecture]  [Core][Database]
   [Secrets]     [Failure]       [Config]
   [Observ.]     [Troubleshoot]
                 [Inference]
```

---

## Package Structure

### Core (@nexus/core)
**Responsibility:** Shared types, events, logging

**Exports:**
- `IProduct` - Product interface
- `IUser` - User type
- `IDeployment` - Deployment type
- `ISecret` - Secret type
- `EventBus` - Event emitter
- `Logger` - Pino logger

**Key Files:**
- `types.ts` - All shared types
- `events.ts` - Event system
- `logger.ts` - Logging infrastructure

---

### API (@nexus/api)
**Responsibility:** REST API endpoint handling

**Key Routes:**
- `GET /health` - Health check
- `GET /api/v1/products` - List products
- `GET/POST /api/v1/ops/*` - OPS endpoints
- `POST /api/v1/diagrams/*` - Diagram generation

**Middleware:**
- CORS
- JSON parsing (50MB limit)
- Request logging
- Error handling

---

### Diagram Engine (@nexus/diagram-engine)
**Responsibility:** Architecture visualization and failure analysis

**Key Classes:**
- `DiagramEngine` - Core diagram generation
  - `generateArchitectureDiagram()` - Create arch diagrams
  - `generateFailureAnalysisDiagram()` - Analyze failures
  - `analyzaFailDetails()` - Root cause analysis
  - `toDraw()` - Convert to Draw.io XML

**Data Flow:**
1. Receive error logs
2. Parse and categorize failures
3. Create diagram representation
4. Run inference to find root cause
5. Generate recommendations
6. Export as Draw.io XML

---

### OPS Product (@nexus/products/ops)
**Responsibility:** Operations management features

**Services:**
- `DeploymentService`
  - List deployments
  - Get deployment details
  - Create deployment
  - Get logs

- `SecretsService`
  - List secrets
  - Get secret details
  - Rotate secrets
  - Policy management

- `ObservabilityService`
  - Get service status
  - Metrics aggregation
  - Health checks
  - SLA monitoring

---

### Security Product (@nexus/products/security) [Future]
**Responsibility:** Security and compliance

**Planned Services:**
- SAST scanning
- DAST scanning
- Dependency analysis
- Compliance management
- Policy enforcement

---

### Frontend (@nexus/frontend)
**Responsibility:** Web UI

**Pages:**
- Dashboard (stats, recent activity)
- Deployments (list, details, history)
- Pipelines (CI/CD status)
- Secrets (management, rotation)
- Observability (metrics, alerts)
- Diagrams (architecture, troubleshooting)
- Infrastructure (resources, topology)
- Settings (configuration)

**Technology:**
- React 18
- Vite (build tool)
- CSS-in-JS (inline styles)
- Fetch API (HTTP)

---

## Data Flow Examples

### Deployment Workflow

```
1. User clicks "Create Deployment"
2. Frontend sends POST /api/v1/ops/deployments
3. API receives request, validates input
4. OPS Product creates deployment object
5. System stores deployment (DB/cache)
6. Returns deployment ID
7. Frontend polls /api/v1/ops/deployments/:id
8. System executes deployment
9. Frontend shows progress via logs endpoint
10. Deployment completes, status updates
```

### Failure Analysis Workflow

```
1. Deployment or service fails
2. Logs are aggregated
3. User clicks "Analyze" button
4. Frontend sends POST /api/v1/diagrams/analyze-failure
5. API receives failure indicators
6. Diagram Engine processes:
   - Identifies affected services
   - Correlates failures
   - Runs inference model
   - Generates diagram
   - Creates recommendations
7. Returns diagram + analysis
8. Frontend displays interactive diagram
9. User can drill into affected nodes for details
```

---

## Integration Points

### External Systems

```
NexusShield Portal
├── Kubernetes API (deployments, pods, logs)
├── Terraform State (infrastructure)
├── Cloud APIs (GCP, AWS, Azure)
├── Vault / GSM / KMS (secrets)
├── Prometheus / Cloud Monitoring (metrics)
├── ELK / GCP Logging (logs)
├── GitLab CI (pipelines)
└── GitHub (events, webhooks)
```

### Repo Integration

All existing repo scripts are wrapped as Portal APIs:

```
scripts/deploy/*       → /api/v1/ops/deployment/*
scripts/monitoring/*   → /api/v1/ops/observability/*
scripts/security/*     → /api/v1/security/*
scripts/ops/*          → /api/v1/ops/*
scripts/test/*         → /api/v1/testing/*
terraform/             → /api/v1/infrastructure/*
docs/runbooks/*        → /api/v1/docs/runbooks/*
```

---

## Scalability Considerations

### Current (Single Instance)
- Single Node.js process
- In-memory event bus
- File-based logging

### Future (Distributed)
- API service (stateless, horizontal scaling)
- Message queue (Kafka/RabbitMQ)
- Distributed event bus
- Persistent database (PostgreSQL)
- Redis for caching
- Elasticsearch for logging

```
┌────────────┐  ┌────────────┐  ┌────────────┐
│   API 1    │  │   API 2    │  │   API 3    │
└─────┬──────┘  └─────┬──────┘  └─────┬──────┘
      │                │                │
      └────────────────┼────────────────┘
                       │
              ┌────────┴────────┐
              │                 │
              ▼                 ▼
        ┌──────────┐      ┌──────────┐
        │ Message  │      │ Database │
        │  Queue   │      │(Postgres)│
        └──────────┘      └──────────┘
              │                 │
              └────────┬────────┘
                       │
                    [Cache]
```

---

## Security Architecture

```
┌─────────────────────────────────────────────────┐
│              Portal API Boundary                 │
├─────────────────────────────────────────────────┤
│                                                  │
│  TLS/HTTPS (in-transit encryption)              │
│  JWT/RBAC (authentication & authorization)      │
│  Rate limiting (DDoS protection)                │
│  Input validation (injection prevention)        │
│  Audit logging (compliance)                     │
│                                                  │
│  ┌────────────────────────────────────────┐    │
│  │      Credential Management Zone         │    │
│  │  (Vault/GSM/KMS - NO HARDCODING)       │    │
│  │  • Database passwords                  │    │
│  │  • API keys                            │    │
│  │  • Cloud credentials (OIDC)            │    │
│  │  • TLS certificates                    │    │
│  └────────────────────────────────────────┘    │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

## Deployment Architecture

### Single Container

```dockerfile
FROM node:18-alpine
COPY built-packages /app
EXPOSE 3000 5000
CMD ["start-both-services"]
```

### Kubernetes (Future)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nexusshield-portal
spec:
  replicas: 3
  containers:
    - name: api
      ports: [5000]
    - name: frontend
      ports: [3000]
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
```

---

## Performance Targets

| Metric | Target | Status |
|--------|--------|--------|
| API p95 latency | <100ms | TBD |
| Portal availability | 99.95% | TBD |
| Diagram generation | <2s | TBD |
| Page load time | <2s | TBD |
| Test coverage | 80%+ | TBD |

---

## Technology Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Frontend | React | 18.2.0 |
| Build Tool | Vite | 5.0.8 |
| Backend | Express.js | 4.18.2 |
| Language | TypeScript | 5.3.3 |
| Package Mgr | pnpm | 8+ |
| Container | Docker | Latest |
| Testing | Vitest | 1.1.0 |
| CI/CD | GitLab CI | Native |

---

## Future Enhancements

1. **Multi-tenancy** - Support multiple customers
2. **Advanced Caching** - Redis for performance
3. **Real-time Features** - WebSocket support
4. **ML Features** - Anomaly detection, predictive alerts
5. **API Gateway** - Kong/Nginx
6. **Message Queue** - Kafka event streaming
7. **Distributed Tracing** - Jaeger integration
8. **GraphQL** - Alongside REST API
9. **Plugins** - Third-party extensions
10. **Mobile App** - React Native or Flutter

---

## Monitoring & Observability

```
Frontend
  ↓
Browser Console Logs
  ↓
Backend
  ↓
Pino Logger → File/Console
            → ELK Stack
            → GCP Cloud Logging
  ↓
Metrics Collection
  ↓
Prometheus
  ↓
Grafana Dashboards
```

---

## Related Documents

- [API Documentation](./API.md)
- [Deployment Guide](./DEPLOYMENT.md)
- [Diagram Engine Guide](./DIAGRAM_ENGINE.md)
- [OPS Product Guide](./OPS_GUIDE.md)
- [Contributing Guide](../CONTRIBUTING.md)

---

**Version History:**
- v1.0 (2026-03-12): Initial architecture definition
