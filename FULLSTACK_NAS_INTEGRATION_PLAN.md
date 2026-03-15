# Full Stack NAS Integration Plan

**Scope:** Complete environment redeployment to use NAS storage  
**Date:** 2026-03-15  
**Status:** PLANNING PHASE

---

## Executive Summary

All services in the repository (frontend, backend, portal, nexus-engine, monitoring, databases, caching) will be redeployed to use centralized NAS storage on 192.168.168.39:/nas (mounted at /nas on 192.168.168.42).

---

## Architecture Overview

### Current Services Discovered

**1. Backend** (Node.js)
- Service: Node.js REST API
- Storage needs: Logs, uploads, cache

**2. Frontend** (Node.js/React)
- Service: Web UI application
- Storage needs: Build artifacts, uploads, logs

**3. Portal** (docker-compose.yml)
- Services: Vite dev server, Node.js backend
- Storage needs: Application files, uploads

**4. Nexus Engine** (Go)
- Service: Processing engine
- Storage needs: Data processing, caches, logs

**5. Webhook Receiver**
- Service: Event processing
- Storage needs: Event logs, queue data

**6. Security Service**
- Service: Security module
- Storage needs: Audit logs, certificates

**7. Monitoring Stack** (from docker-compose.yml)
- PostgreSQL: SSO database
- Keycloak: Identity service
- Prometheus: Metrics
- Grafana: Dashboards
- Nginx: Router
- Storage needs: Database data, metrics, config

---

## NAS Directory Structure

```
/nas/ci-cd/
├── runners/             # (existing, CI/CD runners)
│   ├── runner-42a/
│   ├── runner-42b/
│   └── runner-42c/
├── config/              # (existing, runner config)
├── monitoring/          # (existing, runner monitoring)
│
└── applications/        # (NEW - application services)
    ├── backend/
    │   ├── uploads/
    │   ├── logs/
    │   ├── cache/
    │   └── temp/
    │
    ├── frontend/
    │   ├── build/
    │   ├── uploads/
    │   └── logs/
    │
    ├── portal/
    │   ├── uploads/
    │   ├── data/
    │   └── logs/
    │
    ├── nexus-engine/
    │   ├── data/
    │   ├── cache/
    │   ├── processing/
    │   └── logs/
    │
    ├── webhook/
    │   ├── events/
    │   ├── queue/
    │   └── logs/
    │
    ├── security/
    │   ├── audit/
    │   ├── certificates/
    │   └── logs/
    │
    └── databases/
        ├── postgresql/
        │   ├── keycloak/
        │   ├── appdb/
        │   └── datadir/
        │
        ├── redis/
        │   └── data/
        │
        ├── mongodb/
        │   └── data/
        │
        ├── clickhouse/
        │   └── data/
        │
        ├── prometheus/
        │   └── data/
        │
        └── grafana/
            ├── dashboards/
            ├── provisioning/
            └── data/
```

---

## Deployment Phases

### Phase 1: NAS Structure Creation
- Create all 50+ directories on NAS
- Set proper permissions (755 for app dirs, 700 for sensitive)
- Verify accessibility from all clients

### Phase 2: Backend Integration
- Update backend service to mount `/nas/applications/backend`
- Map logs, uploads, cache to NAS paths
- Create .env configuration
- Deploy and test

### Phase 3: Frontend Integration
- Update frontend build process
- Mount `/nas/applications/frontend` for build artifacts
- Deploy and test

### Phase 4: Portal Integration
- Update docker-compose.portal.yml
- Mount all portal data to NAS
- Deploy and test

### Phase 5: Nexus Engine Integration
- Update nexus-engine processing paths
- Mount `/nas/applications/nexus-engine`
- Deploy and test

### Phase 6: Webhook & Security
- Update webhook receiver mounts
- Configure security service logging to NAS
- Deploy and test

### Phase 7: Monitoring Stack
- Update docker-compose.yml volumes
- PostgreSQL data on NAS
- Prometheus metrics on NAS
- Grafana dashboards on NAS
- Deploy stack and verify

### Phase 8: Verification & Cleanup
- Verify all services running
- Check NAS usage patterns
- Monitor cost tracking
- Update documentation

---

## Storage Allocation

| Component | Allocation | Purpose |
|-----------|-----------|---------|
| Backend | 500GB | Logs, uploads, cache |
| Frontend | 300GB | Build artifacts, uploads |
| Portal | 200GB | Application data |
| Nexus Engine | 1TB | Processing, caches |
| Webhook | 100GB | Events, queue data |
| Security | 50GB | Audit logs |
| PostgreSQL | 500GB | SSO/Application DB |
| Redis | 200GB | Cache data |
| Prometheus | 300GB | Metrics (30-day retention) |
| Grafana | 50GB | Dashboards |
| Reserve | 18TB | Buffer/growth |
|         |        |  |
| **Total** | **22TB** | **Full NAS capacity** |

---

## Mandate Compliance

All 13 mandates maintained throughout full-stack redeployment:

| # | Mandate | Integration |
|---|---------|------------|
| 1 | Immutable audit trail | Git commits for all changes |
| 2 | Zero manual intervention | Automated deployment scripts |
| 3 | Target endpoint .42 | All NAS clients on 192.168.168.42 |
| 4 | Ephemeral cleanup | Container restart policies |
| 5 | NAS mandatory | All persistent data on NAS |
| 6 | Comprehensive logging | All logs → /nas/applications/*/logs |
| 7 | Changes in git | All configs versioned |
| 8 | Production certified | Pre-deployment validation |
| 9 | Cost tracking | Monitor NAS usage patterns |
| 10 | Monitoring stack | Metrics on NAS, dashboards active |
| 11 | Secrets encrypted | GSM for credentials |
| 12 | All runners online | Runners unaffected, separate paths |
| 13 | Disaster recovery | Full backup strategy on NAS |

---

## Rollback Strategy

Each phase includes rollback capability:
- Volume backup before updates
- Original docker-compose saved
- Reverse NAS mounts in 5 minutes
- Zero data loss

---

## Success Criteria

✅ All services running with NAS-backed storage  
✅ No service interruption during deployment  
✅ All logs centralized on NAS  
✅ Database data persisted on NAS  
✅ Metrics and dashboards working  
✅ All 13 mandates maintained  
✅ <2TB used (room for growth)  
✅ Disaster recovery tested  

---

## Timeline

- Phase 1: 30 minutes (directory creation)
- Phase 2-7: 2-3 hours (service deployment)
- Phase 8: 1 hour (verification)
- **Total: 3-4 hours**

---

