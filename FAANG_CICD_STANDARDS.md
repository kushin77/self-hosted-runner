# FAANG Enterprise CI/CD Standards & Enforcement

**Status**: PRODUCTION DEPLOYMENT IN PROGRESS
**Last Updated**: 2026-03-13
**Version**: 2.0-FAANG-ENTERPRISE

---

## Executive Summary

This document defines the FAANG-tier CI/CD standards implemented for the nexusshield-prod repository. These standards enforce security-first, automated, and immutable deployment practices across all services.

---

## Table of Contents

1. [Core Principles](#core-principles)
2. [Governance Standards](#governance-standards)
3. [Deployment Pipeline](#deployment-pipeline)
4. [Security Controls](#security-controls)
5. [Observability & Monitoring](#observability--monitoring)
6. [Testing Framework](#testing-framework)
7. [Operational Procedures](#operational-procedures)
8. [Compliance & Audit](#compliance--audit)

---

## Core Principles

### 1. **No Human Deployments**
- ❌ **NOT ALLOWED**: Manual `kubectl apply`, `gcloud run deploy` 
- ✅ **REQUIRED**: All deployments via Cloud Build automation
- **Enforcement**: Branch protection blocks direct deploys

### 2. **Immutable Infrastructure**
- All deployments create version-controlled artifacts
- Audit trail: JSONL + GitHub + S3 Object Lock (WORM)
- Rollback capability via versioned container images

### 3. **Security-First Automation**
- SBOM generation for all images (Syft + CycloneDX)
- Vulnerability scanning (Trivy) - fail on CRITICAL/HIGH
- Image signing with cosign + KMS
- Signature verification before deployment

### 4. **Zero-Trust Credentials**
- No hardcoded secrets in code/configs
- Google Secret Manager for all secrets
- Ephemeral credentials with TTL enforcement
- Multi-layer failover: STS 250ms → GSM 2.85s → Vault 4.2s

### 5. **Direct-Deploy Model**
- Direct commits to main (no PR-based releases)
- Cloud Build triggers on every main branch commit
- Automated policy checks block non-compliant changes
- Feature flags for gradual rollouts

### 6. **Idempotent Deployments**
- Terraform `plan` shows zero drift on reruns
- Helm deployments idempotent (reapply safely)
- Database migrations versioned
- Service startup idempotent

---

## Governance Standards

### Branch Protection

**Main Branch Rules** (`refs/heads/main`):

```yaml
Required Status Checks:
  - Cloud Build - Policy Check (strict mode)
  - Cloud Build - OpenAPI Validation
  - Cloud Build - Main Build
  - Code Scanning - Security

Required Reviews:
  - Require code owner reviews: true
  - Minimum approvals: 1
  - Dismiss stale reviews: true

Other Protections:
  - Enforce admins: true
  - Require linear history: true
  - Block force pushes: true
  - Block branch deletion: true
```

### Code Ownership (CODEOWNERS)

Critical paths require explicit approval:

```
# All changes
* @kushin77

# Infrastructure & Security
/terraform/ @kushin77
/scripts/ @kushin77
/cloudbuild*.yaml @kushin77

# Sensitive files (require review)
.env* @kushin77
*.key @kushin77
secrets/ @kushin77
```

### GitHub Actions Enforcement

- ✅ **Enabled**: `.github/workflows-archive/` (historical reference only)
- ❌ **Disabled**: All active GitHub Actions workflows
- 🚫 **Blocked**: `.github/workflows/` additions via Cloud Build policy check

**Enforcement Method**:
```bash
# Cloud Build step: Reject any .github/workflows files
if git diff HEAD~1 | grep -E "^[\+\-].*\.github/workflows/"; then
  echo "ERROR: GitHub Actions workflows not allowed"
  exit 1
fi
```

---

## Deployment Pipeline

### Architecture

```
[Commit to main]
        ↓
[Cloud Build Trigger]
        ↓
┌─────────────────────────────────────┐
│ Phase 1: Policy & Security Checks   │
├─────────────────────────────────────┤
│ ✅ Block .github/workflows files    │
│ ✅ Check for hardcoded secrets      │
│ ✅ Validate CODEOWNERS approval     │
│ ✅ OpenAPI spec validation          │
└─────────────────────────────────────┘
        ↓
┌─────────────────────────────────────┐
│ Phase 2: Build & Scan               │
├─────────────────────────────────────┤
│ ✅ Lint (eslint, pylint, etc.)      │
│ ✅ Unit tests                       │
│ ✅ Docker build                     │
│ ✅ SBOM generation (Syft)           │
│ ✅ Vulnerability scan (Trivy)        │
│ ✅ Image signing (cosign)           │
└─────────────────────────────────────┘
        ↓
┌─────────────────────────────────────┐
│ Phase 3: Publication & Deployment   │
├─────────────────────────────────────┤
│ ✅ Push to Artifact Registry        │
│ ✅ Deploy to Cloud Run / K8s        │
│ ✅ Post-deploy verification         │
│ ✅ Audit trail logging              │
└─────────────────────────────────────┘
        ↓
[Production Live]
```

### Cloud Build Configurations

#### `cloudbuild.yaml` - Main Pipeline
- Backend linting
- Frontend build
- SBOM + Trivy scanning
- Image signing
- Cloud Run deployment

#### `cloudbuild.policy-check.yaml` - Policy Enforcement
- Blocks `.github/workflows` additions
- Checks for hardcoded secrets
- Verifies Cloud Build configuration
- Generates compliance reports

#### `cloudbuild.openapi-validation.yaml` - Spec Validation
- Validates OpenAPI spec syntax
- Generates TypeScript types
- Compares spec with implementation
- Archives versioned specs

---

## Security Controls

### 1. Secrets Management

**Primary**: Google Secret Manager (GSM)
**Failover**: HashiCorp Vault
**Last Resort**: AWS KMS

**TTL Enforcement**:
```
Credentials Lifecycle:
- Created: timestamp
- TTL: 24 hours default
- Rotated: every 12 hours
- Revoked: on service changes
```

### 2. Image Security

**SBOM (Software Bill of Materials)**:
- Generated: syft (SPDX + CycloneDX formats)
- Stored: gs://nexusshield-prod-sbom-archive
- Retention: 1 year (immutable)

**Vulnerability Scanning**:
```bash
trivy image \
  --severity CRITICAL,HIGH \
  --exit-code 1 \
  gcr.io/nexusshield-prod/service:${SHA}
```

**Image Signing**:
```bash
cosign sign --key kms://gcp/projects/nexusshield-prod/...
gcr.io/nexusshield-prod/service:${SHA}
```

### 3. API Security

**Circuit Breaker Pattern**:
- Protects against cascading failures
- Auto-recovery after configurable timeout
- Metrics: open/half-open/closed states
- Example: `backend/circuit_breaker.py`

**RLS (Row-Level Security)**:
- PostgreSQL policies enforce tenant isolation
- Application layer validation
- Database-level enforcement

### 4. Audit Trail

**Immutable Logging**:
```jsonl
{
  "timestamp": "2026-03-13T14:30:00Z",
  "action": "deployment",
  "service": "nexus-shield-portal-backend",
  "image": "gcr.io/nexusshield-prod/.../backend:abc1234",
  "operator": "cloud-build",
  "status": "success"
}
```

**Storage**:
- Primary: GitHub audit logs
- Secondary: S3 Object Lock COMPLIANCE bucket (365-day retention)
- Queryable: BigQuery tables

---

## Observability & Monitoring

### Health Checks

**Automated Checks** (via Cloud Scheduler):

```bash
# Hourly
- Cloud Run services health
- Kubernetes cluster health  
- Database connectivity
- GCS bucket compliance

# Daily
- Certificate expiration
- Outdated dependencies
- Image vulnerabilities
- Quota usage
```

### Self-Healing Automation

**Script**: `scripts/self-healing/self-healing-infrastructure.sh`

**Capabilities**:
- Detects unhealthy services
- Auto-retries failed deployments
- Remediates stale resources
- Validates IAM permissions
- Generates compliance reports

### Metrics & Observability

**Prometheus**:
- Application metrics ()
- Resource utilization
- API latency percentiles (p50, p95, p99)

**Grafana**:
- Pre-built dashboards
- Alert rules
- Compliance dashboard

**OpenTelemetry + Jaeger**:
- Distributed tracing
- Service dependency visualization
- Latency analysis

---

## Testing Framework

### E2E Testing

**Coverage**:
- ✅ Happy path scenarios (normal operations)
- ✅ Edge cases (boundary conditions)
- ✅ Error handling (404, 500, timeouts)
- ✅ Security (auth, injection attacks, DoS)
- ✅ Performance (latency thresholds)
- ✅ Integration (multi-service workflows)

**Framework**: `tests/e2e_test_framework.py`

**Execution**:
```bash
pytest tests/e2e_test_framework.py -v --asyncio-mode=auto

# For specific category
pytest tests/e2e_test_framework.py -k "security" -v
```

**Success Criteria**:
- 95%+ test success rate
- p99 latency < 500ms
- No HIGH/CRITICAL security issues

### Unit Tests

**Requirements**:
- Minimum 80% code coverage
- CI job: `npm run test:unit`
- Failure blocks deployment

### Integration Tests

**Scope**:
- Credentials API ↔ Database
- Portal API ↔ Backend services
- Kafka pipeline ↔ Normalizer

---

## Operational Procedures

### Deployment Checklist

**Pre-Deployment**:
- [ ] Cloud Build policy check passes
- [ ] SBOM generated (CRITICAL/HIGH vulnerability scan)
- [ ] Image signed with KMS key
- [ ] E2E tests pass (95%+ success)
- [ ] CODEOWNERS approvals obtained

**Deployment Execution**:
- [ ] Cloud Build triggered on main commit
- [ ] All phases complete successfully
- [ ] Services update to new version
- [ ] Post-deploy verification runs

**Post-Deployment**:
- [ ] Health checks pass (all services)
- [ ] Audit trail logged
- [ ] Metrics within normal range
- [ ] No alerts triggered

### Emergency Procedures

**Circuit Breaker Activation**:
- Service transitions to OPEN state
- Requests fail fast (not cascading)
- Automatic recovery attempted after timeout
- On-call team alerted

**Rollback Procedure**:
1. Identify previous stable image SHA
2. Capture incident details
3. Revert deployment to previous version
4. Verify service health
5. Log incident to audit trail
6. Post-mortem analysis

**Branch Protection Bypass**:
- Only for life-critical incidents
- Requires 2 admin approvals
- Auto-revert after 10 minutes
- Full audit trail logged

### Maintenance Windows

**Preferred**: Tuesday 02:00-04:00 UTC
- Low traffic period
- On-call team available
- Infrastructure monitoring active

### Runbooks

- **nexus-shield-portal** (`docs/runbooks/portal-operations.md`)
- **Kafka Pipeline** (`docs/runbooks/kafka-pipeline.md`)
- **Database** (`docs/runbooks/database-operations.md`)
- **GCP Infrastructure** (`docs/runbooks/gcp-operations.md`)

---

## Compliance & Audit

### Governance Verification (8/8 Status)

✅ **Immutable**: JSONL + GitHub + S3 Object Lock WORM
✅ **Idempotent**: Terraform plan shows zero drift
✅ **Ephemeral**: Credential TTLs enforced
✅ **No-Ops**: 5 daily Cloud Scheduler jobs + 1 weekly CronJob
✅ **Hand-Off**: OIDC token auth (no passwords)
✅ **Multi-Credential**: 4-layer failover SLA 4.2s
✅ **No-Branch-Dev**: Direct commits to main only
✅ **Direct-Deploy**: Cloud Build → Cloud Run (no release workflow)

### Audit Trail Requirements

**Captured**:
- Deployment timestamp + operator
- Service + image SHA + version
- Build status + logs
- Security scan results
- All manual interventions

**Retention**:
- GitHub: unlimited
- S3 Object Lock: 365 days (immutable)
- BigQuery: queryable historical

### Compliance Standards

- **SLSA Level 3**: Builds provenance tracking
- **NIST**: Cryptographic signing + audit logging
- **SOC 2 Type II**: Ready (observability + access controls)

---

## Related Documentation

- [OPERATIONAL_HANDOFF_FINAL_20260312.md](./OPERATIONAL_HANDOFF_FINAL_20260312.md)
- [OPERATOR_QUICKSTART_GUIDE.md](./OPERATOR_QUICKSTART_GUIDE.md)
- [PRODUCTION_DEPLOYMENT_COMPLETION_FINAL_20260312.md](./PRODUCTION_DEPLOYMENT_COMPLETION_FINAL_20260312.md)
- [DEPLOYMENT_BEST_PRACTICES.md](./DEPLOYMENT_BEST_PRACTICES.md)

---

## Contact & Escalation

**On-Call**: @kushin77
**Escalation**: @BestGaaS220
**Incident Channel**: #incidents

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 2.0-FAANG-ENTERPRISE | 2026-03-13 | SLSA Level 3, Circuit Breaker, E2E Testing |
| 1.9 | 2026-03-12 | Self-Healing Automation |
| 1.8 | 2026-03-11 | OpenAPI Validation, Branch Protection |
| 1.7 | 2026-03-10 | Initial FAANG Standards Rollout |

---

**Document Status**: APPROVED FOR PRODUCTION
**Last Review**: 2026-03-13
**Next Review**: 2026-04-13
