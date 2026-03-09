# Secrets & Runbooks Completeness Audit

This document verifies that all secrets, credentials, and operational runbooks are properly documented, audited, and have emergency procedures in place.

## Secrets Inventory & Storage

### GitHub Repository Secrets
Location: [Repository Settings → Secrets and variables → Actions](https://github.com/kushin77/self-hosted-runner/settings/secrets/actions)

| Secret | Purpose | Rotation | Backup Store |
|--------|---------|----------|--------------|
| `GITHUB_TOKEN` | Repository automation (workflows, issues, Draft issues) | Auto-renewed by GitHub | N/A |
| `RUNNER_MGMT_TOKEN` | GitHub PAT with `administration:read` scope for managing runners | Manual / AppRole rotation | GCP GSM, Vault |
| `DEPLOY_SSH_KEY` | Private SSH key for Ansible provisioning and recovery | Annual or on-demand | GCP GSM, Vault |
| `MINIO_ENDPOINT` | S3-compatible MinIO endpoint URL | N/A (static config) | GCP GSM |
| `MINIO_ACCESS_KEY` | MinIO access key ID | Annual or on-demand | GCP GSM, Vault |
| `MINIO_SECRET_KEY` | MinIO secret key | Annual or on-demand | GCP GSM, Vault |
| `VAULT_ADDR` | HashiCorp Vault server address | N/A (static) | Documentation |
| `VAULT_ROLE_ID` | AppRole role ID for Vault authentication | N/A (static) | Documentation |
| `VAULT_SECRET_ID` | AppRole secret ID for Vault authentication | Monthly (auto-rotated) | Vault backend |

### GCP Secret Manager (GSM) Secrets
Location: [GCP Cloud Console → Security → Secret Manager](https://console.cloud.google.com/security/secret-manager)

All GitHub Actions secrets are mirrored in GSM for centralized IAM and audit logging. See [GSM_VAULT_INTEGRATION.md](GSM_VAULT_INTEGRATION.md) for setup and access details.

### HashiCorp Vault Secrets
Location: `secret/runner/*` in Vault instance at `$VAULT_ADDR`

Dynamic credentials are stored and rotated via Vault AppRole. See [GSM_VAULT_INTEGRATION.md](GSM_VAULT_INTEGRATION.md) for rotation procedures.

---

## Runbooks & Operational Documentation

### Phase 3 Closure
- **Document**: [DEPLOYMENT_READY.md](archive/DEPLOYMENT_READY.md)
- **Status**: ✅ Complete
- **Coverage**:
  - Artifact release to GitHub (immutable, checksummed)
  - MinIO archival (secondary backup)
  - Self-attestation and sign-off
- **Emergency Procedure**: If Phase 3 artifacts are lost, restore from GitHub Release or MinIO

### Phase 4 Self-Healing
- **Document**: [ROADMAP.md](../actions-runner/externals.2.332.0/node24/lib/node_modules/npm/node_modules/smart-buffer/docs/ROADMAP.md) (Section: Phase 4 — Operational Resilience)
- **Workflows**: 
  - [runner-self-heal.yml](../.github/workflows/runner-self-heal.yml) — Automated recovery
  - [credential-monitor.yml](../.github/workflows/credential-monitor.yml) — Trigger detection
- **Status**: ✅ Complete
- **Coverage**:
  - Automated runner health checks and remediation
  - Fallback to SSH/Ansible if API credentials are missing
  - Issue tracking and notifications
- **Emergency Procedure**: Manual Ansible playbook execution at `ansible/playbooks/provision-self-hosted-runner-noninteractive.yml`

### Credential Rotation
- **Document**: [GSM_VAULT_INTEGRATION.md](GSM_VAULT_INTEGRATION.md) (Section: AppRole Rotation)
- **Workflow**: `.github/workflows/rotate-vault-approle.yml` (quarterly)
- **Status**: 📝 To be implemented
- **Coverage**:
  - Automated AppRole secret ID refresh
  - GitHub secret updates
  - Audit trail in Vault
- **Emergency Procedure**: Manual `vault write -f auth/approle/role/gh-runner/secret-id` and `gh secret set VAULT_SECRET_ID`

### Disaster Recovery (DR) & Archival
- **Document**: [DEPLOYMENT_FINAL_STATUS.md](../DEPLOYMENT_FINAL_STATUS.md)
- **Workflows**:
  - [phase3-minio-upload.yml](../.github/workflows/phase3-minio-upload.yml) — Scheduled/manual archival
  - [docker-hub-weekly-dr-testing.yml](../.github/workflows/docker-hub-weekly-dr-testing.yml) — Dry-run validation
- **Status**: ✅ Workflow ready; blocked by DNS for `mc.elevatediq.ai`
- **Coverage**:
  - Automated artifact backup to MinIO (S3-compatible)
  - Weekly DR dry-run tests
  - MinIO access control and versioning
- **Emergency Procedure**: Manual upload via `scripts/minio/upload.sh` if workflow fails

### Security & Audit
- **Document**: This file ([SECRETS_RUNBOOKS_AUDIT.md](SECRETS_RUNBOOKS_AUDIT.md))
- **Audit Scope**:
  - GitHub Actions secrets audit log (GitHub Dashboard)
  - GCP GSM audit logs (Cloud Logging)
  - Vault audit logs (local `/var/log/vault/audit.log`)
- **Status**: ✅ Logging configured
- **Coverage**:
  - Secret access logs and alerts
  - Rotation history
  - Configuration change tracking
- **Emergency Procedure**: Review audit logs for unauthorized access; rotate compromised credentials immediately

---

## Checklist: Runbooks & Documentation Completeness

### Phase 3 Artifacts & Release
- [x] GitHub Release created with checksums
- [x] MinIO archival workflow configured
- [x] Artifact integrity validated (SHA256)
- [x] Recovery procedure documented
- [x] Fallback (GitHub Release) tested

### Phase 4 Self-Healing & Monitoring
- [x] Self-heal workflow deployed and tested
- [x] Credential monitoring scheduled and triggered
- [x] Issue creation on failure
- [x] SSH/Ansible fallback configured
- [x] Runner health checks automated

### Secrets Management
- [x] GitHub Actions secrets configured
- [x] GCP GSM integration documented
- [x] Vault AppRole setup documented
- [x] Rotation procedures defined
- [ ] Automated rotation workflows deployed (pending Vault access)
- [x] Emergency credential revocation documented

### Documentation
- [x] GSM & Vault integration guide
- [x] Self-heal runbook
- [x] MinIO archival workflow
- [x] Runner provisioning guide (Ansible)
- [x] Emergency recovery procedures
- [x] Audit trail setup (GCP, Vault, GitHub)
- [x] Secrets inventory (this document)

### Testing & Validation
- [x] Phase 3 closure dry-run passed
- [x] Self-heal workflow triggered and confirmed
- [x] Credential monitor workflow executed
- [x] MinIO upload configured (DNS pending)
- [x] GitHub Release integrity verified
- [ ] End-to-end DR test with recovered artifacts (pending DNS)
- [ ] Vault credential rotation test (pending Vault access)

---

## Outstanding Tasks

### Short-term (Blocking)
1. **NetOps DNS**: Add A/CNAME record for `mc.elevatediq.ai` (Issue #1007)
   - Current Status: Open, assigned to NetOps
   - Unblocks: MinIO archival and DR testing

2. **SSH Key Audit Approval**: Approve key ID `142804975` for git pushes (Issue #1008)
   - Current Status: Awaiting admin approval at https://github.com/settings/keys/142804975
   - Unblocks: Git pushes and PR creation

### Medium-term
1. **Vault Access Setup**: Deploy Vault AppRole credentials and rotation workflow
   - Requires: Vault instance access and policies
   - Enables: Automated AppRole secret rotation

2. **GSM Sync Workflow**: Deploy `.github/workflows/sync-gsm-to-github-secrets.yml`
   - Requires: GCP service account credentials in GitHub
   - Interval: Every 6 hours

3. **End-to-End DR Test**: Restore Phase 3 artifacts from MinIO and validate
   - Requires: MinIO DNS resolution working
   - Validation: Decompress artifacts and verify checksums

### Long-term
1. **Quarterly Rotation Schedule**: Implement quarterly rotation for all long-lived credentials
   - AppRole secret ID (already monthly)
   - RUNNER_MGMT_TOKEN (PAT refresh)
   - DEPLOY_SSH_KEY (key rotation)

2. **Audit Log Aggregation**: Centralize audit logs from GitHub, GCP, Vault into SIEM
   - Tools: GCP Cloud Logging, Vault audit backend, GitHub audit log API

---

## Access Control & Permissions

### GitHub Repository
- **Admins**: @akushnir, team leads
- **Write Access**: CI automation (via `GITHUB_TOKEN`)
- **Read Access**: Workflow runners, team members

### GCP Project
- **Admin Role**: Project admins
- **Secret Manager Access**: Service account with `secretmanager.secretAccessor` role
- **Audit Viewer**: Security/ops team

### HashiCorp Vault
- **Admin Policy**: `admin` policy for initial setup
- **AppRole Policy**: `runner-policy` for CI/CD access
- **Audit Viewer**: Ops team reviewing `/var/log/vault/audit.log`

### MinIO
- **Bucket Owner**: MinIO admin account
- **Write Access**: CI workflows (via `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY`)
- **Read Access**: Disaster recovery personnel

---

## Sign-Off

- **Documentation Audit**: ✅ Completed 2026-03-07
- **Runbook Coverage**: ✅ Phase 3 & Phase 4 complete; GSM/Vault in progress
- **Emergency Procedures**: ✅ Defined for all critical paths
- **Next Review Date**: 2026-06-07 (quarterly)

For updates or questions, file an issue or contact the ops team.
