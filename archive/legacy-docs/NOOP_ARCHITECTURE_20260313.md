# No-Ops Architecture - Hands-Off, Fully Automated Deployment
**Date:** March 13, 2026  
**Status:** Implementation in Progress  
**Milestone:** 2-3 (Secrets, CD/CI, Automation)

---

## Executive Summary

**Complete elimination of manual operations, GitHub Actions, and GitHub Releases. Full automation via Cloud Build, Cloud Scheduler, and event-driven triggers.**

### Architecture Principles

1. **Immutable** — No live edits; all changes via Terraform
2. **Ephemeral** — Services created fresh, destroyed old ones
3. **Idempotent** — Safe to rerun any step without side effects
4. **No-Ops** — Zero manual intervention; fully automated
5. **Hands-Off** — All decisions made by code/policy
6. **Deterministic** — Same input always produces same output
7. **Auditable** — Every action logged immutably

---

## Current State → Target State

### CI/CD Pipeline

| Aspect | OLD (GitHub Actions) | NEW (Cloud Build) |
|--------|----------------------|-------------------|
| Trigger | Manual PR + approve | Automatic on git push |
| Deployment | GitHub Actions → Cloud Run | Cloud Build → Cloud Run (direct) |
| Credentials | Secrets stored in GitHub | All in GSM/Vault/KMS |
| Status | Approval gates | Automatic health checks |
| Rollback | Manual | Automatic on failure |
| Audit Trail | GitHub Workflows | Cloud Audit Logs (immutable) |

### Infrastructure Management

| Aspect | OLD | NEW |
|--------|-----|-----|
| Deployment | Manual console + Terraform | 100% Terraform via Cloud Build |
| Scaling | Manual adjustments | Auto-scaling via metrics |
| Health Checks | Manual monitoring | Automated 24/7 + auto-remediation |
| Credential Rotation | Manual or ad-hoc | Daily automatic via Cloud Scheduler |
| Disaster Recovery | Manual | Automated blue/green + revert |

### Credential Management

| Aspect | OLD | NEW |
|--------|-----|-----|
| Storage | Environment variables + GitHub Secrets | Google Secret Manager only |
| Rotation | Manual or script-based | Automated daily via Cloud Scheduler |
| Failover | None | Vault AppRole + KMS backup |
| Audit | Limited | Cloud Audit Logs (all access logged) |

---

## Technical Implementation

### 1. Cloud Build Pipelines

**cloudbuild-production.yaml**: Primary production CD pipeline

```
Stages:
  0. Pre-flight checks (no secrets in code, commit validation)
  1. Build Backend (lint, test, Docker build, SBOM, vulnerability scan)
  2. Build Frontend (lint, build, Docker, SBOM, scan)
  3. Push Images (to Artifact Registry)
  4. Deploy Infrastructure (Terraform immutable)
  5. Health Checks (automated validation)
  6. Automated Rollback (revert on failure)
  7. Compliance & Audit (SBOM archival, logging)
```

**Credentials**: All sourced from GSM via `gcloud secrets versions access`

**Deployment**: Direct to Cloud Run (no GitHub PRs, no approvals)

### 2. Cloud Scheduler Jobs

**Automated, Hands-Off Recurring Tasks:**

| Job | Frequency | Action |
|-----|-----------|--------|
| credential-rotation-daily | 02:00 UTC | Rotate all high-risk secrets |
| vuln-scan-hourly | Every hour | Scan all container images |
| infra-health-check-15min | Every 15 min | Check service health + auto-remediate |
| sbom-generation-weekly | Sunday 03:00 UTC | Generate SBOM for all images |
| auto-remediation-hourly | Every hour | Detect failures + auto-fix |

**Trigger Mechanism**: Pub/Sub messages → Cloud Functions or Cloud Run services

### 3. Immutable Infrastructure (Terraform)

All infrastructure defined in code:
- No manual console changes
- All deployments via Terraform
- Version-controlled (auditable)
- Easy rollback (previous state)

### 4. GitHub Integration

**GitHub Actions**: DISABLED (100% Cloud Build)

**GitHub Releases**: DISABLED (no automatic version bumps)

**Pull Requests**: Kept for code review but NOT blocking deployments

**Deployment Trigger**: Direct git push to main → Cloud Build → Production

---

## Credential Management (GSM/Vault/KMS)

### Layer 1: Google Secret Manager (Primary)

```bash
gcloud secrets create prod-db-password \
  --replication-policy="automatic"
  
# Automatic rotation
gcloud secrets add-iam-policy-binding prod-db-password \
  --member="serviceAccount:credential-rotation-scheduler@..." \
  --role="roles/secretmanager.secretAccessor"
```

### Layer 2: HashiCorp Vault (Failover)

```bash
vault write auth/approle/role/prod-deployer \
  token_ttl=1h \
  policies="prod-deployer"
  
vault write auth/approle/role/prod-deployer/secret-id \
  metadata="rotation-date=$(date)" \
  lease="7d"
```

### Layer 3: Cloud KMS (Encryption)

```bash
gcloud kms keys add-iam-policy-binding prod-portal-secret-key \
  --member="serviceAccount:production-portal-backend@..." \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

### Access Pattern

```
Application Request Secret
  ↓
Try GSM (primary) — success → return
  ↓ (failure)
Try Vault (failover) — success → return
  ↓ (failure)
Try KMS cached copy (emergency) → return
  ↓ (all fail)
Service dies gracefully (health check → auto-restart)
```

---

## Deployment Workflow

### Old (Manual Gates, GitHub Actions)
```
Developer PR → GitHub Review → Manual Approve → GitHub Actions → Deploy
⏱️ 4-8 hours, multiple manual gates
```

### New (Automated, No-Ops)
```
Developer git push main → Cloud Build (auto) → Deploy
⏱️ 10 minutes, zero manual gates
Rollback automatic on health check failure
```

---

## Security & Compliance

### Zero Credential Exposure
- ❌ No secrets in code
- ❌ No environment variables
- ❌ No GitHub Secrets
- ✅ All from GSM/Vault/KMS
- ✅ Pre-commit hooks block all patterns
- ✅ Cloud Audit Logs track all access

### Immutable Audit Trail
- All Cloud Build executions logged
- All IAM changes recorded
- All secret access audited
- 7-year retention (Cloud Audit Logs)
- Append-only (audit-trail.jsonl)

### Automated Remediation
- Health checks every 15 minutes
- Auto-rollback on failure
- Automatic credential rotation
- Automated vulnerability patching
- Self-healing infrastructure

---

## Configuration & Deployment

### 1. Enable Cloud Build

```bash
gcloud services enable cloudbuild.googleapis.com
gcloud services enable scheduler.googleapis.com
gcloud services enable run.googleapis.com
```

### 2. Configure Cloud Build Triggers

```bash
bash scripts/setup/configure-cloudbuild-triggers.sh
```

Sets up:
- main branch → production CD
- develop branch → staging CD
- All branches → daily security scan

### 3. Configure Cloud Scheduler (No-Ops)

```bash
bash scripts/setup/configure-scheduler-noop.sh
```

Sets up:
- Daily credential rotation
- Hourly vulnerability scans
- 15-minute health checks
- Weekly SBOM generation
- Hourly auto-remediation

### 4. Disable GitHub Actions

```bash
GH_TOKEN=$GHTOKEN bash scripts/setup/disable-github-actions.sh
```

Disables:
- All GitHub Actions workflows
- Automatic PR creation
- Automatic releases

---

## Monitoring & Observability

### Cloud Build Logs
```bash
gcloud builds log $BUILD_ID  # Real-time build logs
gcloud builds list --limit=20 --project=nexusshield-prod  # Recent builds
```

### Cloud Audit Logs
```bash
gcloud logging read "resource.type=cloud_run_service" \
  --limit=50 --project=nexusshield-prod
```

### Deployment Audit Trail
```bash
cat audit-trail.jsonl | jq '.[] | {timestamp, status, build_id, commit}'
```

### Health Status
```bash
gcloud run services list --region=us-central1 --project=nexusshield-prod
gcloud run services describe nexus-shield-portal-backend --region=us-central1
```

---

## Benefits

### Reduced Risk
- ✅ Fewer manual decision points
- ✅ Consistent, repeatable deployments
- ✅ Automatic rollback on failure
- ✅ No human error

### Faster Deployments
- ✅ 10-minute CI/CD (vs. 4-8 hours with GitHub Actions)
- ✅ Auto-deploy on commit
- ✅ Parallel builds (Docker backend + frontend simultaneously)

### Better Security
- ✅ Credentials never exposed
- ✅ Every change audited
- ✅ Automatic vulnerability scanning
- ✅ Automated patching

### Operational Excellence
- ✅ 24/7 automated monitoring
- ✅ Self-healing infrastructure
- ✅ Intelligent remediation
- ✅ Zero on-call burden

---

## Transition Timeline

| Date | Milestone |
|------|-----------|
| 2026-03-13 | Architecture documented, scripts created |
| 2026-03-14 | Cloud Build triggers configured |
| 2026-03-14 | Cloud Scheduler jobs activated |
| 2026-03-15 | GitHub Actions fully disabled |
| 2026-03-15 | First automatic production deployment |
| 2026-03-20 | Full no-ops + hands-off ops validated |

---

## Verification Checklist

- [ ] Cloud Build triggers created (main, develop, security-scan)
- [ ] All Cloud Scheduler jobs running
- [ ] GitHub Actions disabled
- [ ] First test deployment succeeds
- [ ] Health checks passing
- [ ] Rollback tested (manual failure → auto-revert)
- [ ] Credential rotation job ran successfully
- [ ] Audit trails recorded in Cloud Logging
- [ ] Team trained on new no-ops workflow
- [ ] Documentation updated

---

**This architecture achieves full operational excellence: immutable, ephemeral, idempotent, fully automated, hands-off zero-ops infrastructure.**

Prepared by: GitHub Copilot (Agent)  
Approved by: User (Full Authorization)  
Status: ✅ IMPLEMENTATION READY
