# Infrastructure Governance & Compliance Policy

**Effective Date:** March 5, 2026  
**Last Updated:** March 5, 2026  
**Status:** PRODUCTION ENFORCED

---

## Architecture Mandate

### Deployment Model - STRICT ENFORCEMENT (Non-Negotiable)

```
CONTROL PLANE (192.168.168.31) - NO RUNNING SERVICES
  ├─ Role: Management, Ops, Monitoring Dashboards Only
  ├─ Allowed: kubectl, terraform, git operations, health checks
  └─ FORBIDDEN: Node.js services, database servers, API backends, workers

WORKER NODE (192.168.168.42) - ALL INFRASTRUCTURE RUNS HERE
  ├─ Portal Frontend: 0.0.0.0:3919
  ├─ Observability Stack: Prometheus (9095), Alertmanager (9096), Grafana (3000)
  ├─ Runner Services: Provisioner Worker, Pipeline Repair, AI Oracle
  ├─ Data Services: Redis, PostgreSQL (if applicable)
  └─ All backend APIs and worker processes
```

---

## Governance Rules

### Rule 1: Service Deployment Locations
**Severity:** CRITICAL | **Enforcement:** Automatic

- ✅ **ALLOWED on 192.168.168.42 (Worker):**
  - All Node.js services (Portal, APIs, Workers)
  - All database services (Redis, PostgreSQL)
  - All monitoring services (Prometheus, Grafana, Alertmanager)
  - All provisioner and runner services
  - All background workers and job processors

- ❌ **FORBIDDEN on 192.168.168.31 (Control):**
  - Node.js processes with `npm run dev` or `vite`
  - Docker containers with service ports exposed
  - Database servers
  - Worker processes
  - Any service with a listening port except management tools (kubectl proxy, etc.)

### Rule 2: Node.js Version Requirements
**Severity:** CRITICAL | **Enforcement:** Build-time & Runtime

- **Minimum Version:** Node 20.19.0 (for Vite 7.3.1 compatibility)
- **Recommended:** Node 22.x LTS or Node 24.x
- **Maximum Age:** 3 months behind current LTS
- **Testing Requirement:** All PRs must test on Node 20.19+ and 22.x

### Rule 3: Port Allocation & Binding
**Severity:** HIGH | **Enforcement:** Runtime Validation

| Service | Port | Bind Host | Node | Status |
|---------|------|-----------|------|--------|
| Portal (Dev) | 3919 | 0.0.0.0 | 192.168.168.42 | ACTIVE |
| Portal (Prod) | 3919 | 0.0.0.0 | 192.168.168.42 | ACTIVE |
| Prometheus | 9095 | 0.0.0.0 | 192.168.168.42 | ACTIVE |
| Alertmanager | 9096 | 0.0.0.0 | 192.168.168.42 | ACTIVE |
| Grafana | 3000 | 0.0.0.0 | 192.168.168.42 | ACTIVE |
| API Backend | [configurable] | 0.0.0.0 | 192.168.168.42 | BY_ENV |
| Redis | 6379 | 127.0.0.1 | 192.168.168.42 | BY_ENV |

**Compliance Check:** No service should bind to localhost (127.0.0.1) or respond on control plane (192.168.168.31).

### Rule 4: Environment Variable Enforcement
**Severity:** HIGH | **Enforcement:** Build & Deployment

All deployments must define and validate:

```bash
# Control Plane Validation
CONTROL_PLANE_ENABLED=false          # Services DO NOT run here
ALLOW_LOCALHOST_SERVICES=false       # npm dev, vite strictly forbidden
ENFORCE_WORKER_DEPLOYMENT=true       # All traffic to 192.168.168.42

# Worker Node Requirement  
WORKER_NODE_ENDPOINT=192.168.168.42  # All services connect here
REQUIRE_REMOTE_HOST=true             # Bind to 0.0.0.0, not localhost
MIN_NODE_VERSION=20.19.0             # Vite requirement
```

### Rule 5: CI/CD Pipeline Compliance
**Severity:** HIGH | **Enforcement:** GitHub Actions

- All PRs must pass infrastructure governance checks
- Node.js version matrix must include: 20.19+, 22.x, 24.x (when stable)
- Docker images MUST specify Node 20+ baseline
- Terraform plans MUST target 192.168.168.42, never localhost
- Deployment scripts MUST validate target node before execution

---

## Compliance Checks

### Pre-Deployment Validation Checklist

```bash
# 1. Node Version Check
node --version  # Must be >= 20.19.0

# 2. Service Port Check (should fail on control plane)
netstat -tlnp | grep -E ':(3919|9095|9096|3000)'  # Must be EMPTY on 192.168.168.31

# 3. Environment Validation
echo $WORKER_NODE_ENDPOINT  # Should be 192.168.168.42
echo $CONTROL_PLANE_ENABLED # Should be false

# 4. Docker Compose Validation
docker-compose config | grep -E 'build:|node:|image:'  # Must reference worker node

# 5. Terraform Validation
terraform plan | grep -E '192\.168\.168\.'  # Should target 192.168.168.42, NOT 192.168.168.31
```

---

## Enforcement Mechanisms

### 1. Pre-Commit Hooks (REQUIRED)
Files: `.husky/pre-commit`, `.git/hooks/pre-commit`

```bash
# Reject commits with localhost binding in production configs
grep -r "localhost\\|127.0.0.1" \
  --include="*.yml" --include="*.yaml" \
  --include="docker-compose*" \
  deploy/ && exit 1 || true
```

### 2. GitHub Actions CI Checks (ENFORCED)
All PRs must pass workflows:
- `.github/workflows/infrastructure-governance.yml`
- `.github/workflows/node-version-matrix.yml`
- `.github/workflows/deployment-validation.yml`

### 3. Runtime Polling (MONITORING)
Monitor script runs every 5 minutes on control plane:

```bash
# Fail if Node.js service detected on localhost
ps aux | grep -E 'node|npm|vite' | grep -v grep && \
  echo "VIOLATION: Service running on control plane!" && \
  exit 1
```

### 4. Network Policy Enforcement (K8s)
If using Kubernetes, network policies restrict:
- Ingress to 192.168.168.42 only for proxy traffic
- Egress from control plane limited to management APIs

---

## Escalation Procedures

| Violation | Detection | Action | Owner |
|-----------|-----------|--------|-------|
| Service running on ctrl plane | Automated hook | Kill process & fail commit | Developer |
| Node < 20.19 detected | CI check | Fail PR, request matrix test | CI/CD Lead |
| Non-worker deployment in terraform | Code review + validation | Reject PR | Platform Eng |
| Runtime port bind to localhost | Monitoring alert | Page SRE, kill container | SRE On-Call |

---

## Exceptions & Waivers

**All exceptions require:**
1. GitHub Issue creation with justification
2. CTO/Platform Lead approval (required review)
3. Automatic expiration: 30 days
4. Post-exception root cause analysis

**Example exception:** Temporary local testing (must include end-date and mitigation plan)

---

## Audit & Reporting

### Monthly Compliance Report
- [ ] All services running on 192.168.168.42
- [ ] Zero localhost services in production configs
- [ ] All Docker images Node 20+ compatible
- [ ] All deployments passed governance checks
- [ ] Zero violations in git history (last 30 days)

### Compliance Dashboard
Endpoint: `192.168.168.42:3000/compliance`
- Current violations
- Services by node
- Node.js version distribution
- Deployment compliance score

---

## Change Management

**Policy Updates Require:**
1. GitHub issue labelled `governance`
2. Review from minimum 2 platform engineers
3. 7-day notice period before enforcement changes
4. Update to this document with `[DATE] UPDATED` stamp

---

## Questions or Violations?

Open a GitHub issue with label `governance` or contact the platform team.

**Policy Owner:** Platform Engineering  
**Last Review:** 2026-03-05
