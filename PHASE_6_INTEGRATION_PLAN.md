# Phase 6: Portal MVP Integration Plan
**Status:** Ready for Implementation  
**Date:** 2026-03-10  
**Constraint Model:** Immutable · Ephemeral · Idempotent · No-Ops  

## Overview
Phase 6 integrates all Portal MVP components (frontend, backend, database, observability) into a cohesive deployment unit. This phase bridges Phases 1-5 (infrastructure) and Phase 7-9 (production hardening).

---

## 1. Core Integration Points

### 1.1 Frontend-Backend Integration
```
Frontend Dashboard → API Gateway → Backend Services
   (React/Vite)        (Kong)         (FastAPI/Go)
      :3000             :8000           :8080
```

**Tasks:**
- [ ] Configure API endpoint discovery (service mesh or DNS)
- [ ] Implement request/response middleware
- [ ] Add authentication token passing (JWT/OIDC)
- [ ] Setup CORS properly
- [ ] Add request tracing headers

**Verification:**
```bash
# Check API connectivity
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/api/health
```

### 1.2 Database Integration
```
Backend → Database Driver → PostgreSQL
(Connection Pooling)     (migrations applied)
```

**Tasks:**
- [ ] Apply all pending migrations (backend/migrations/*.sql)
- [ ] Verify database user permissions
- [ ] Setup connection pooling (pgbouncer or app-level)
- [ ] Validate schema integrity
- [ ] Configure backup strategy

**Verification:**
```bash
# Check migrations
psql -U portal_user -d portal_db -c "\dt"
```

### 1.3 Observability Integration
```
App Metrics → Prometheus → Grafana
Log Stream → Loki        → Grafana
Traces     → Jaeger       → Grafana
```

**Tasks:**
- [ ] Instrument FastAPI app (prometheus-client)
- [ ] Configure metric scrape targets
- [ ] Setup log aggregation (Promtail → Loki)
- [ ] Enable distributed tracing
- [ ] Create Grafana dashboards

---

## 2. Testing Strategy

### 2.1 Integration Tests
```
Phase 6 Integration Test Suite
├── API Contract Tests
│   ├── Frontend calls backend
│   ├── Response validation
│   └── Error handling
├── Database Tests
│   ├── CRUD operations
│   ├── Migration rollback
│   └── Constraint validation
└── E2E Tests
    ├── User workflows
    ├── Data consistency
    └── Error scenarios
```

**Implementation:**
- [ ] Create integration test fixtures
- [ ] Implement API contract tests (Pact)
- [ ] Write database tests (pytest-postgresql)
- [ ] Setup Cypress E2E tests
- [ ] Configure test result reporting

### 2.2 Test Execution Plan
```
pytest backend/tests/integration/ \
  --cov=backend \
  --cov-report=xml \
  --junitxml=test-results.xml

cypress run \
  --headless \
  --browser=chrome \
  --spec="cypress/e2e/*.cy.ts"
```

---

## 3. Deployment Configuration

### 3.1 Development Environment
```yaml
version: '3.8'
services:
  frontend:
    build: frontend/
    ports: ["3000:3000"]
    env_file: .env.local
  
  backend:
    build: backend/
    ports: ["8080:8080"]
    depends_on: [database]
    env_file: .env.backend
  
  database:
    image: postgres:15
    ports: ["5432:5432"]
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backend/migrations:/docker-entrypoint-initdb.d
    environment:
      POSTGRES_DB: portal_db
      POSTGRES_USER: portal_user
      POSTGRES_PASSWORD: ${DB_PASSWORD}
```

**Deploy:**
```bash
docker-compose -f docker-compose.dev.yml up -d
```

### 3.2 Local Environment Setup
```bash
# 1. Frontend
cd frontend
npm install
npm run build     # production build
npm run dev       # develop mode

# 2. Backend
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python -m pytest tests/
python -m uvicorn main:app --reload

# 3. Database
psql -U postgres
CREATE DATABASE portal_db;
GRANT ALL ON DATABASE portal_db TO portal_user;

# Apply migrations
psql -U portal_user -d portal_db \
  -f migrations/001_init.sql \
  -f migrations/002_users.sql
```

---

## 4. Health Check & Monitoring

### 4.1 Health Endpoints
```
/health                 → Overall system health
/health/frontend        → Frontend build status
/health/backend         → API service status
/health/database        → Database connectivity
/health/observability   → Metrics/logging status
```

### 4.2 Metrics to Track
```
Frontend:
  - Page load time (Core Web Vitals)
  - API call latency
  - Error rate
  - User session count

Backend:
  - Request rate (RPS)
  - Response latency (p50, p95, p99)
  - Error rate (4xx, 5xx)
  - Database query time
  - Cache hit ratio

Database:
  - Connection count
  - Query duration
  - Transaction rollback rate
  - Storage usage
  - Replication lag (if applicable)
```

---

## 5. Immutable Audit Trail

All Phase 6 operations must append to audit log:

```jsonl
{"timestamp":"2026-03-10T10:00:00Z","phase":"6","action":"integration_test_start","component":"api","status":"in_progress"}
{"timestamp":"2026-03-10T10:05:23Z","phase":"6","action":"api_contract_test","result":"pass","duration_ms":543}
{"timestamp":"2026-03-10T10:10:15Z","phase":"6","action":"db_migration_applied","migration":"002_users","status":"success"}
{"timestamp":"2026-03-10T10:15:00Z","phase":"6","action":"e2e_test_suite","result":"pass","passed":47,"failed":0}
{"timestamp":"2026-03-10T10:20:00Z","phase":"6","action":"integration_verification_complete","status":"success"}
```

**Storage:** `logs/portal-mvp-phase6-*.jsonl` (immutable, append-only)

---

## 6. Success Criteria

| Criterion | Metric | Target | Status |
|-----------|--------|--------|--------|
| **Frontend-Backend** | API calls successful | 100% | ○ |
| **Database** | All migrations applied | 100% | ○ |
| **Transactions** | ACID compliance | 100% | ○ |
| **E2E Tests** | Pass rate | 100% | ○ |
| **Performance** | API latency | <100ms p95 | ○ |
| **Observability** | Metrics visible | All 3 stacks | ○ |
| **Audit Trail** | Immutable log | All operations | ○ |

---

## 7. Rollback Plan

If Phase 6 integration fails:

1. **Revert to Phase 5 State**
   ```bash
   git checkout main  # Restore last working state
   ```

2. **Database Rollback**
   ```bash
   # Manual rollback if migration broken
   psql -U portal_user -d portal_db \
     -f migrations/rollback/002_users_down.sql
   ```

3. **Container Cleanup**
   ```bash
   docker-compose down --volumes
   ```

4. **Audit Logging**
   ```json
   {"phase":"6","action":"rollback","reason":"integration_failure","timestamp":"..."}
   ```

---

## 8. Phase 6 Timeline

| Task | Duration | Dependencies | Owner |
|------|----------|--------------|-------|
| Frontend-backend wiring | 2-4h | Phases 1-5 complete | Frontend Lead |
| Database schema validation | 1-2h | Backend complete | DBA |
| Integration tests setup | 3-4h | Both complete | QA Lead |
| Observability config | 2-3h | Monitoring stack ready | DevOps |
| E2E test execution | 2-3h | Frontend ready | QA Lead |
| Verification & audit | 1-2h | All above | Lead |

**Total: 11-19 hours (1-2 days)**

---

## 9. Handoff Checklist

Before Phase 7, verify:

- [ ] All 4 integration points verified
- [ ] Integration test suite passing (100%)
- [ ] E2E test suite passing (100%)
- [ ] Health endpoints responding
- [ ] Audit trail complete (immutable log)
- [ ] Performance benchmarks met
- [ ] Observability dashboards active
- [ ] Database backups configured
- [ ] Documentation updated
- [ ] Team trained on Portal MVP

---

## 10. Next Phase (Phase 7)

Once Phase 6 complete, Phase 7 focuses on:
- Production hardening
- Security scanning
- Load testing
- Chaos engineering
- Production deployment

---

**Document Status:** Ready for Implementation  
**Last Updated:** 2026-03-10 09:00 UTC  
**Next Review:** After Phase 6 completion
