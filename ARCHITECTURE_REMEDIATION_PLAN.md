# 🏗️ Architecture Remediation Plan
## Mandatory On-Premises-First Deployment Compliance

**Date**: 2026-03-14  
**Status**: ENFORCEMENT PHASE  
**Urgency**: ⛔ BLOCKING - Must complete before production deployment

---

## Executive Summary

This document outlines the complete remediation strategy to enforce mandatory deployment constraints:

- ✅ **All application workloads** → 192.168.168.42 (on-premises)
- ✅ **Secrets management** → Cloud (GSM/Vault)  
- ✅ **Rebuild artifacts** → Cloud (IaC state, configs)
- ❌ **No production on** 192.168.168.31 (dev workstation only)

**Total Files to Remediate**: 14 configuration files across 4 priority tiers

---

## Implementation Strategy

### Phase 1: Quick Wins (Priority 1 & 2) - **TARGET: Today**
- Docker Compose files for core services
- Kubernetes manifest node selectors

### Phase 2: Supporting Services (Priority 3) - **TARGET: Today**
- Monitoring and exporter configurations
- Prometheus scrape targets

### Phase 3: Documentation (Priority 4) - **TARGET: Tomorrow**
- API documentation references
- Ansible playbook targets

### Phase 4: Validation & Deployment (All Phases)
- Run compliance script on all files
- Deploy with validation
- Create audit trail

---

## PRIORITY 1: Production Docker Compose Files

### Files to Remediate (6 total)

#### 1. `portal/docker-compose.yml`
**Purpose**: Core portal service  
**Current Issue**: Likely uses localhost/127.0.0.1  
**Required Changes**:
```yaml
# Pattern A: Service Networking
services:
  portal:
    environment:
      - API_HOST=192.168.168.42      # ← PRIMARY: Use on-prem IP
      - API_PORT=8080
      - DATABASE_HOST=192.168.168.42 # ← Database on on-prem
      - CACHE_HOST=192.168.168.42    # ← Cache on on-prem
    deploy:
      placement:
        constraints:
          - node.role == worker       # ← Ensure on-prem node

# Pattern B: Network Configuration  
networks:
  app-network:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.168.0/24   # ← On-prem subnet
```

**Validation**:
```bash
grep -E "192.168.168.42" portal/docker-compose.yml || echo "FAIL"
grep -E "localhost|127.0.0.1" portal/docker-compose.yml && echo "VIOLATION" || echo "PASS"
```

---

#### 2. `portal/docker/docker-compose.yml`
**Purpose**: Portal Docker service definition  
**Current Issue**: May have conflicting local references  
**Required Changes**:
- Replace all `localhost` with `192.168.168.42`
- Update service DNS names to resolve via on-prem
- Add explicit node constraints

---

#### 3. `frontend/docker-compose.dashboard.yml`
**Purpose**: Frontend dashboard service  
**Current Issue**: Frontend typically binds to localhost  
**Required Changes**:
```yaml
services:
  dashboard:
    ports:
      - "192.168.168.42:3000:3000"  # ← Bind to on-prem IP
    environment:
      - BACKEND_URL=http://192.168.168.42:8080  # ← Backend on-prem
      - API_GATEWAY=192.168.168.42:9000
```

**Note**: Keep internal container port as-is (3000), but bind external to on-prem IP

---

#### 4. `frontend/docker-compose.loadbalancer.yml`
**Purpose**: Load balancer for frontend  
**Current Issue**: Likely hardcoded to localhost backends  
**Required Changes**:
```yaml
services:
  load-balancer:
    environment:
      - BACKEND_POOL=192.168.168.42:3000,192.168.168.42:3001
      - LISTEN_ADDR=192.168.168.42
      - LISTEN_PORT=80
```

---

#### 5. `nexus-engine/docker-compose.yml`
**Purpose**: Nexus engine core service  
**Current Issue**: May reference localhost for dependencies  
**Required Changes**:
```yaml
services:
  nexus-engine:
    environment:
      - WEBHOOK_HOST=192.168.168.42
      - WEBHOOK_PORT=8080
      - DISCOVERY_ENDPOINT=http://192.168.168.42:8080/discover
    networks:
      - nexus-net
    deploy:
      placement:
        constraints:
          - node.labels.region == onprem
```

---

#### 6. `ops/github-runner/docker-compose.yml`
**Purpose**: GitHub Actions runner  
**Current Issue**: May have localhost webhook callbacks  
**Required Changes**:
```yaml
services:
  github-runner:
    environment:
      - RUNNER_CALLBACK=http://192.168.168.42:8080/webhook
      - STATE_SERVER=192.168.168.42:6379
      - AUDIT_ENDPOINT=192.168.168.42:9200
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    deploy:
      placement:
        constraints:
          - node.role == manager || node.role == worker
```

---

## PRIORITY 2: Kubernetes Orchestration

### Files to Remediate (3 total)

#### 1. `kubernetes/phase1-deployment.yaml`
**Status**: ✅ **MOSTLY COMPLIANT**  
**Current State**: Has proper on-prem constraints  
**Verification Markers**:
```yaml
labels:
  deployment-region: onprem
spec:
  nodeSelector:
    worker-node: onprem
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node-type
            operator: In
            values:
            - onprem-worker-42  # ← CORRECT
```

**Minor Checks**:
- ✅ Service references use ClusterIP (internal)
- ✅ No external LoadBalancer to localhost
- ✅ Metrics endpoints on on-prem IP

---

#### 2. `k8s/deployment-strategies.yaml`
**Purpose**: Deployment strategy definitions  
**Required Changes**:
```yaml
# Ensure all strategies reference on-prem nodes
strategies:
  canary:
    nodeSelector:
      region: onprem
      capacity: standard
  
  blue-green:
    nodeSelector:
      region: onprem
      capacity: large
```

---

#### 3. `monitoring/elite-observability.yaml`
**Purpose**: Advanced observability stack  
**Required Changes**:
```yaml
# Prometheus deployment
spec:
  nodeSelector:
    workload-type: monitoring
    region: onprem
  
# Alert targets
alerting:
  targets:
    - 192.168.168.42:9093  # ← On-prem alertmanager
```

---

## PRIORITY 3: Monitoring & Exporters

### Files to Remediate (4 total)

#### 1. `config/docker-compose.node-exporter.yml`
**Purpose**: Node-level metrics collection  
**Required Pattern**:
```yaml
services:
  node-exporter:
    environment:
      - PROMETHEUS_HOST=192.168.168.42
      - PROMETHEUS_PORT=9090
    ports:
      - "192.168.168.42:9100:9100"  # ← Expose on on-prem
```

---

#### 2. `config/docker-compose.postgres-exporter.yml`
**Purpose**: Database metrics  
**Required Pattern**:
```yaml
services:
  postgres-exporter:
    environment:
      - DATA_SOURCE_NAME=postgresql://user:pass@192.168.168.42:5432/metrics
      - LISTEN_ADDR=192.168.168.42:9187
```

---

#### 3. `config/docker-compose.redis-exporter.yml`
**Purpose**: Cache metrics  
**Required Pattern**:
```yaml
services:
  redis-exporter:
    environment:
      - REDIS_ADDR=192.168.168.42:6379
      - LISTEN_ADDR=192.168.168.42:9121
```

---

#### 4. `monitoring/prometheus.yml`
**Purpose**: Prometheus main configuration  
**Required Pattern**:
```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'kubernetes'
    static_configs:
      - targets: ['192.168.168.42:10250']  # ← Kubelet on-prem
  
  - job_name: 'postgresql'
    static_configs:
      - targets: ['192.168.168.42:9187']   # ← PG exporter
  
  - job_name: 'redis'
    static_configs:
      - targets: ['192.168.168.42:9121']   # ← Redis exporter
  
  - job_name: 'nexus'
    static_configs:
      - targets: ['192.168.168.42:9090']   # ← Nexus metrics
```

---

## PRIORITY 4: Documentation & Playbooks

### Files to Review (2 total)

#### 1. `api/openapi.yaml`
**Purpose**: API documentation  
**Status**: Documentation only - lower priority  
**Verification**:
```yaml
servers:
  - url: http://192.168.168.42:8080
    description: Production (On-Premises)
  - url: http://192.168.168.42:9000
    description: API Gateway (On-Premises)
```

---

#### 2. `portal/ansible/deploy-portal.yml`
**Purpose**: Ansible deployment playbook  
**Required Pattern**:
```yaml
---
- hosts: onprem_workers
  vars:
    target_host: 192.168.168.42
    app_port: 8080
    db_host: 192.168.168.42
    cache_host: 192.168.168.42
  
  tasks:
    - name: Deploy portal to on-prem
      docker_container:
        name: portal
        image: portal:latest
        env:
          API_HOST: "{{ target_host }}"
```

---

## Compliance Verification Script

Save as `scripts/verify-architecture-compliance.sh`:

```bash
#!/bin/bash
set -euo pipefail

VIOLATIONS=0
COMPLIANT=0

verify_file() {
  local file="$1"
  local type="${2:-yaml}"
  
  if [[ ! -f "$file" ]]; then
    echo "⚠️  SKIPPED: $file (not found)"
    return 0
  fi
  
  echo -n "Checking $file ... "
  
  # Check for violations
  if grep -q "127.0.0.1\|localhost" "$file"; then
    # It's only bad if there's no .42 reference
    if ! grep -q "192.168.168.42\|onprem\|on-prem" "$file" 2>/dev/null; then
      echo "❌ VIOLATION: localhost/127.0.0.1 without .42"
      VIOLATIONS=$((VIOLATIONS + 1))
      return 1
    fi
  fi
  
  if grep -q "192.168.168.31" "$file"; then
    echo "❌ VIOLATION: Prohibited .31 reference"
    VIOLATIONS=$((VIOLATIONS + 1))
    return 1
  fi
  
  echo "✅ COMPLIANT"
  COMPLIANT=$((COMPLIANT + 1))
  return 0
}

echo "🔍 ARCHITECTURE COMPLIANCE AUDIT"
echo "=================================="
echo ""

echo "PRIORITY 1 - Docker Compose (Production)"
verify_file "portal/docker-compose.yml" "yaml"
verify_file "portal/docker/docker-compose.yml" "yaml"
verify_file "frontend/docker-compose.dashboard.yml" "yaml"
verify_file "frontend/docker-compose.loadbalancer.yml" "yaml"
verify_file "nexus-engine/docker-compose.yml" "yaml"
verify_file "ops/github-runner/docker-compose.yml" "yaml"
echo ""

echo "PRIORITY 2 - Kubernetes"
verify_file "kubernetes/phase1-deployment.yaml" "yaml"
verify_file "k8s/deployment-strategies.yaml" "yaml"
verify_file "monitoring/elite-observability.yaml" "yaml"
echo ""

echo "PRIORITY 3 - Monitoring"
verify_file "config/docker-compose.node-exporter.yml" "yaml"
verify_file "config/docker-compose.postgres-exporter.yml" "yaml"
verify_file "config/docker-compose.redis-exporter.yml" "yaml"
verify_file "monitoring/prometheus.yml" "yaml"
echo ""

echo "PRIORITY 4 - Documentation"
verify_file "api/openapi.yaml" "yaml"
verify_file "portal/ansible/deploy-portal.yml" "yaml"
echo ""

echo "📊 RESULTS"
echo "=================================="
echo "✅ Compliant:    $COMPLIANT"
echo "❌ Violations:   $VIOLATIONS"
echo ""

if [[ $VIOLATIONS -eq 0 ]]; then
  echo "🎉 ALL SYSTEMS COMPLIANT"
  exit 0
else
  echo "⛔ REMEDIATION REQUIRED"
  exit 1
fi
```

**Run verification**:
```bash
chmod +x scripts/verify-architecture-compliance.sh
bash scripts/verify-architecture-compliance.sh
```

---

## Deployment Checklist

### Pre-Deployment
- [ ] All PRIORITY 1-3 files remediated
- [ ] Compliance script returns all green (0 violations)
- [ ] Network connectivity verified (192.168.168.31 ↔️ 192.168.168.42)
- [ ] On-prem infrastructure capacity verified

### Deployment
- [ ] Docker Compose services deployed to 192.168.168.42
- [ ] Kubernetes cluster on on-prem nodes
- [ ] All services accessible via on-prem IPs
- [ ] Monitoring endpoints reporting metrics
- [ ] Secrets remain in cloud (GSM/Vault)

### Post-Deployment
- [ ] Verify all service IPs resolve to 192.168.168.42
- [ ] Confirm no services on 192.168.168.31
- [ ] Test inter-service communication
- [ ] Validate metrics collection
- [ ] Document as baseline

### Rollback Plan
- If deployment fails, revert files from git
- Stop services on on-prem
- Verify cloud (secrets/artifacts) unaffected
- Re-run compliance script
- File incident with logs

---

## Status Tracking

| Phase | Item | Status | Owner | ETA |
|-------|------|--------|-------|-----|
| 1 | PRIORITY 1 files | 📝 In Progress | DevOps | Today |
| 2 | PRIORITY 2 validation | 🔄 Blocked | DevOps | Today |
| 3 | PRIORITY 3 updates | 🔄 Blocked | DevOps | Today |
| 4 | PRIORITY 4 review | 🔄 Blocked | DevOps | Tomorrow |
| 5 | Compliance script | 🔄 Blocked | DevOps | Today |
| 6 | Full validation | 🔄 Blocked | DevOps | Today |
| 7 | Production deployment | 🔄 Blocked | DevOps | Tomorrow |

---

## Architecture Diagram

```
SECURITY BOUNDARY: 192.168.168.0/24
┌─────────────────────────────────────────────┐
│                ON-PREMISES                   │
│            192.168.168.42 (Node)             │
│                                              │
│  ✅ Kubernetes Cluster                       │
│  ✅ Docker Swarm Services                    │
│  ✅ PostgreSQL Database                      │
│  ✅ Redis Cache                              │
│  ✅ Prometheus (metrics)                     │
│  ✅ Alertmanager                             │
│  ✅ Webhook Receiver                         │
│  ✅ API Gateway                              │
│  ✅ Portal Services                          │
│                                              │
└─────────────────────────────────────────────┘
          ↕ (Network: Internal 192.168.168.0/24)
┌─────────────────────────────────────────────┐
│           DEVELOPMENT WORKSTATION            │
│            192.168.168.31 (Laptop)           │
│                                              │
│  ❌ NO PRODUCTION SERVICES                   │
│  ✅ Orchestration Commands                   │
│  ✅ kubectl/docker CLI                       │
│  ✅ Git operations                           │
│  ✅ Development IDEs                         │
│                                              │
└─────────────────────────────────────────────┘
          ↕ (Network: SSH/HTTP)
┌─────────────────────────────────────────────┐
│            CLOUD (GCP/AWS)                   │
│                                              │
│  ✅ Google Secret Manager (GSM)              │
│  ✅ AWS Secrets Manager                      │
│  ✅ Vault (external)                         │
│  ✅ Terraform State (GCS/S3)                 │
│  ✅ Build Artifacts (Container Registry)     │
│  ✅ Documentation (Cloud Storage)             │
│                                              │
│  ❌ NO APPLICATION WORKLOADS                 │
│  ❌ NO DATABASES                             │
│  ❌ NO SERVICES                              │
│                                              │
└─────────────────────────────────────────────┘
```

---

## Reference Files

- Constraint documentation: `CRITICAL-DEPLOYMENT-CONSTRAINTS.md`
- On-premises infrastructure: `memories/repo/on-premises-infrastructure.md`
- Service account architecture: `memories/repo/service-account-architecture.md`

---

## Approval & Sign-Off

This remediation plan is **MANDATORY** and must be completed before production deployment.

**Status**: 🔴 BLOCKING  
**Severity**: 🔴 CRITICAL  
**Target Completion**: 2026-03-14 EOD

---

**Document Version**: 1.0  
**Last Updated**: 2026-03-14  
**Next Review**: When compliance reaches 100%
