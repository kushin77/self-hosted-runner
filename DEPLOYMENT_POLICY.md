# DEPLOYMENT POLICY & STANDARDS

**Effective Date:** 2026-03-11  
**Status:** ✅ ACTIVE & ENFORCED

---

## Executive Summary

All deployments follow **immutable, ephemeral, idempotent, hands-off** principles with zero manual intervention. This policy ensures production reliability, security, and compliance.

---

## Deployment Framework

### Property Requirements

Every deployment MUST satisfy:

| Property | Definition | Verification |
|----------|-----------|--------------|
| **Immutable** | All operations logged to append-only JSONL; no edits/deletes | `logs/bootstrap-deployment-*.jsonl` immutable |
| **Ephemeral** | Credentials generated at runtime, not stored in repo | No `.env` files, all secrets via GSM/Vault/KMS |
| **Idempotent** | Safe to run repeatedly; no duplicate/conflicting operations | Terraform plans show "no changes" on re-run |
| **No-Ops** | Zero manual steps; fully automated from commit to production | No runbooks requiring human action |
| **Hands-Off** | Zero human intervention required after deployment trigger | No monitoring dashboards that require human action |

### Credential Management Strategy

**NEVER hardcode secrets in any form:**

```bash
# ❌ DO NOT DO THIS
export DATABASE_URL="postgres://user:password@host/db"
ENV DATABASE_URL="postgres://user:password@host/db"
secrets.env  # File in repo

# ✅ DO THIS
export DATABASE_URL=$(get_secret database-url)  # Fetched at runtime from GSM
```

**Runtime Secret Retrieval (multi-layer fallback):**

```
Vault (primary, if configured)
    ↓
Google Secret Manager (secondary, production)
    ↓
AWS Secrets Manager (tertiary, if configured)
    ↓
Environment Variables (last resort)
    ↓
Default / Auto-generated
```

### Deployment Path (No GitHub Actions, Direct to Main)

```
Developer Commits → git push origin main
    ↓
CI/CD Webhook Triggered (systemd timer or Cloud Build trigger)
    ↓
Immutable Audit Event: "deployment_triggered"
    ↓
Bootstrap Deployment Script Executes
    ├─ GCP Infrastructure Provisioned
    ├─ Container Images Built & Pushed
    ├─ Cloud Run Services Deployed
    ├─ Health Checks Verified
    └─ Audit Trail Logged
    ↓
GitHub Issues Created for Tracking
    ↓
Immutable Audit Event: "deployment_complete"
    ↓
✅ DEPLOYMENT LIVE
```

**Zero GitHub Actions, Zero PR-Based Releases:**
- `.github/workflows/` is empty (no CI pipelines)
- All changes committed directly to `main`
- Releases created via git tags, not pull request merges
- No approval gates or manual intervention

---

## Deployment Checklist

### Pre-Deployment

- [ ] All code changes committed to `main` (no PRs)
- [ ] Container Dockerfile updated (if applicable)
- [ ] Terraform state clean and committed
- [ ] Secrets provisioned in GSM/Vault/KMS
- [ ] GitHub issues reviewed (blocking issues resolved)

### Deployment Execution

- [ ] Trigger deployment: `bash scripts/deploy/deploy.sh`
- [ ] Audit trail logged to `logs/bootstrap-deployment-*.jsonl`
- [ ] Container images built and pushed
- [ ] Cloud Run services deployed
- [ ] Health checks passing

### Post-Deployment

- [ ] GitHub tracking issues created
- [ ] Health check endpoints responding
- [ ] Audit trail immutably stored
- [ ] Logs archived to multi-region cloud storage
- [ ] Team notified (if monitoring enabled)

---

## Credential Rotation

**Automated daily:**
```bash
# Runs via systemd timer
systemctl status nexusshield-credential-rotation.timer

# Manual trigger
bash scripts/credential-rotation.sh
```

**Rotation process:**
1. Generate new secret value (random, appropriately-scoped)
2. Store in GSM (creates new version, keeps history)
3. Sync to Vault (AppRole + KV v2)
4. Update running services (graceful reload)
5. Archive old secret (for 7-year retention)
6. Log rotation event to immutable audit trail

**Operator responsibility:** Monthly review of rotation logs
```bash
grep '"event": "secret_rotated"' logs/deployment-audit-*.jsonl | tail -20
```

---

## Security Requirements

### Secret Storage

| Secret | Primary | Secondary | Retention | Rotation |
|--------|---------|-----------|-----------|----------|
| `database-url` | GSM | Vault KV | 7 years | Daily |
| `redis-password` | GSM | Vault KV | 7 years | Daily |
| `portal-admin-key` | GSM | Vault KV | 7 years | Daily |
| `portal-mfa-secret` | GSM | Vault KV | 7 years | Monthly (manual) |
| Service account keys | GSM | Vault | 7 years | Auto-revoked after 30d |

### Encryption

- **At Rest:** KMS key encryption for all GSM secrets
- **In Transit:** TLS 1.3 for all API calls (gcloud, Vault, AWS APIs)
- **Audit Trail:** Optionally encrypted with KMS (immutability is primary protection)

### Access Control

- **GCP:** Workload Identity (no long-lived service account keys)
- **Vault:** AppRole with time-limited secret IDs (30-minute TTL)
- **GitHub:** Personal access tokens stored as "Machine tokens" in vault (limited scope)

---

## Disaster Recovery

### Recovery from Backup

All artifacts archived for recovery:
- Container images (tagged, immutable)
- Terraform state (versioned)
- Database snapshots (hourly)
- Configuration exports (Git history)

**10-Minute Recovery Target:**
```bash
# From archived state, restore any cloud in 10 minutes
bash scripts/cloud/skeleton-mode-restore.sh --cloud gcp
```

---

## Compliance & Audit

### SOC 2 Type II Alignment

- ✅ **Immutable Audit Trail:** JSONL append-only, cryptographic chaining
- ✅ **Change Management:** Every operation logged, who/when/what tracked
- ✅ **Access Controls:** RBAC per environment, Workload Identity
- ✅ **Encryption:** At rest (KMS), in transit (TLS 1.3)
- ✅ **Incident Response:** Automated rollback on health check failure

### HIPAA Compliance Checklist

- ✅ **Encryption:** All data encrypted at rest and in transit
- ✅ **Access Logs:** Audit trail logs all credential accesses
- ✅ **Integrity:** Hash-chain verification on JSONL entries
- ✅ **Availability:** 99.999% uptime SLA, auto-failover
- ✅ **Breach Notification:** Automated alerts for suspicious activity

---

## Policy Enforcement

### Automated Verification

Run periodically to verify compliance:

```bash
# Check: No GitHub Actions present
bash scripts/policy/enforce-no-github-actions.sh

# Check: No hardcoded secrets in repo
bash scripts/policy/scan-for-secrets.sh

# Check: All credentials use multi-layer providers
bash scripts/policy/verify-secret-providers.sh

# Check: Audit trail immutable
bash scripts/policy/verify-audit-immutability.sh
```

### Violations & Remediation

| Violation | Detection | Remediation |
|-----------|-----------|------------|
| Hardcoded secret in repo | Secret scanner (periodic) | Remove immediately, rotate secret, extend audit trail |
| GitHub Actions workflow added | Policy enforcement script | Delete, explain violation, adjust access controls |
| Direct SSH to production | Cloud Log analysis | Document in ticket, review for legitimate access |
| Credential not rotated in 30d | Automated alert | Rotate immediately, extend ticket |

---

## Approval & Enforcement

### Who Can Deploy?

**Automated Deployments:** CI/CD system (systemd timer or Cloud Build trigger)
- Requires: Valid commit to `main`
- No human approval needed

**Manual Deployments:** Infrastructure operators only
- Requires: GCP credentials + Terraform access
- Audit trail captures operator ID + timestamp

### Change Authorization

All changes must be:
1. Committed to `main` (via direct commit, no PRs)
2. Code reviewed locally (GitHub review optional, not blocking)
3. Tested in staging (if applicable)
4. Documented in GitHub issue
5. Deployed via automated script (no manual SSH/kubectl)

---

## Rollback Policy

### Automatic Rollback

Triggered automatically on:
- Health check failure (3 consecutive failures)
- Error rate spike (>1% 5xx errors)
- Cloud Run service unhealthy
- Terraform plan shows destructive changes (requires manual override)

```bash
# Automatic rollback execution
gcloud run services update-traffic "$SERVICE_NAME" \
    --region "$GCP_REGION" \
    --to-revisions LATEST=0 PREVIOUS=100
```

### Manual Rollback

If automatic rollback fails:

```bash
# Rollback to previous known-good revision
bash scripts/release/rollback.sh --revision previous-good

# Or restore from backup
bash scripts/cloud/skeleton-mode-restore.sh --cloud gcp
```

---

## Monitoring & Alerting

### Deployment Notifications

When deployment completes:
1. GitHub issue updated with status
2. Slack notification (if configured)
3. Email notification (optional)
4. Audit trail entry logged

### Health Check Monitoring

Continuous monitoring of:
- API endpoints (HTTP 200 check)
- Database connectivity (ping)
- Cache availability (Redis PING)
- Disk usage (alert at 85%)
- CPU/Memory utilization (baseline ±20%)

**Alert Thresholds:**
```
Latency p99       > baseline + 10%  → Warning
Error Rate        > 0.1%            → Critical
Database Lag      > 5 seconds       → Critical
Disk Usage        > 85%             → Warning
CPU Utilization   > 80%             → Warning
```

---

## Related Documents

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — How to deploy
- [scripts/deploy/bootstrap-deployment.sh](scripts/deploy/bootstrap-deployment.sh) — Bootstrap entrypoint
- [CREDENTIAL_MANAGEMENT_GSM.md](CREDENTIAL_MANAGEMENT_GSM.md) — Secret provisioning details
- [NO_GITHUB_ACTIONS.md](NO_GITHUB_ACTIONS.md) — Policy enforcement

---

## Questions?

For questions about this policy:
1. Check GitHub issues #2313-#2413
2. Review immutable audit trail (`logs/deployment-audit-*.jsonl`)
3. Run deployment in verbose mode: `--verbose`
4. Contact infrastructure team

---

**Status:** ✅ ACTIVE & ENFORCED  
**Last Review:** 2026-03-11  
**Next Review:** Quarterly (or after major incident)
