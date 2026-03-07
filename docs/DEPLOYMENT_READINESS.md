# Deployment Readiness: Immutable, Sovereign, Ephemeral, Hands-Off CI/CD

**Status**: Ready for pre-flight validation  
**Date**: March 6, 2026  
**Objective**: Enable fully automated, audit-gated, ephemeral runner deployments with secure Vault AppRole provisioning and sovereign MinIO artifact storage.

---

## Executive Summary

This repository now includes end-to-end automation for immutable, sovereign, ephemeral, and fully automated deployments. All infrastructure components are in place:

- ✅ **Vault AppRole Provisioning**: Idempotent CLI + HTTP fallback helper (`scripts/ci/setup-approle.sh`)
- ✅ **MinIO Artifact Storage**: Self-hosted artifact repository with migration helpers (`scripts/minio/*`)
- ✅ **Hands-off Deploy Flow**: Guarded, optional secret persistence and approval gating
- ✅ **Pipeline Resilience**: Enhanced retry strategy with exponential backoff and escalation
- ✅ **E2E Validation**: One-click smoke-test and guarded hands-off deploy workflow
- ✅ **Documentation**: Runbook, helper scripts, and policies

---

## Pre-Requisites: What You Need to Enable

### 1. Repository Secrets (MinIO Artifact Storage)

Add these 4 secrets to **Settings → Secrets and variables → Actions → Repository secrets**:

```bash
gh secret set MINIO_ENDPOINT --body "https://mc.elevatediq.ai:9000" --repo kushin77/self-hosted-runner
gh secret set MINIO_ACCESS_KEY --body "minioadmin" --repo kushin77/self-hosted-runner
gh secret set MINIO_SECRET_KEY --body "minioadmin-secretkey" --repo kushin77/self-hosted-runner
gh secret set MINIO_BUCKET --body "github-actions-artifacts" --repo kushin77/self-hosted-runner
```

**Required permissions**: The MinIO service account must have `PutObject` and `GetObject` permissions on the bucket.

### 2. Environment Approvers (Gated AppRole Provisioning)

The `deploy-approle` environment exists but has no required reviewers yet. To enable gated provisioning:

**Via GitHub UI**:
1. Go to **Settings → Environments → deploy-approle**
2. Check "Required reviewers"
3. Add team or user approvers (e.g., `@your-org/infra-admins`)

**Via API** (if you have admin token):
```bash
gh api repos/:owner/:repo/environments/deploy-approle/protection/rules \
  --input - <<'EOF'
{
  "required_reviewers": [{"type": "Team", "id": 123456}]
}
EOF
```

### 3. Optional: Vault Admin Token (Auto-Provisioning)

If you want workflows to auto-provision AppRoles without manual intervention, set:

```bash
gh secret set VAULT_ADMIN_TOKEN --body "s.abc123..." --repo kushin77/self-hosted-runner
```

This enables the `setup-approle` step in deploy workflows to run automatically (still gated by environment approval).

### 4. Optional: GitHub Admin Token (Secret Persistence)

If you want the hands-off deploy to persist generated AppRole credentials to repo secrets automatically:

```bash
gh secret set GITHUB_ADMIN_TOKEN --body "ghp_..." --repo kushin77/self-hosted-runner
```

**Minimal scope**: `repo` + `actions:write` + `secrets:write` (or just `secrets:write` if your token is more restrictive).

---

## How to Validate: E2E Smoke Test

Once repository secrets are in place, run the E2E validation workflow:

### Option A: GitHub UI
1. Go to **Actions → "E2E Validate & Hands-off Deploy"**
2. Click **"Run workflow"**
3. Leave `run_deploy = true`
4. Click **"Run workflow"**

### Option B: Command Line
```bash
gh workflow run e2e-validate.yml --repo kushin77/self-hosted-runner --field run_deploy=true
```

### What the E2E Workflow Does
1. **Check secrets**: Validates `MINIO_*` secrets are present
2. **Upload to MinIO**: Tests artifact uploading with a test file
3. **Download from MinIO**: Tests artifact downloading and verifies checksum
4. **Dispatch hands-off deploy**: If all checks pass, triggers `deploy-rotation-staging` with `hands_off=true`

### Expected Output
- MinIO smoke-test passes → upload/download succeeds → checksum matches
- Dispatch step succeeds → `deploy-rotation-staging` workflow created
- Check Actions → Workflows → find `deploy-rotation-staging` run to see deployment progress

---

## How the Hands-Off Deploy Works

The `deploy-rotation-staging` workflow (`.github/workflows/deploy-rotation-staging.yml`):

1. **Accepts inputs**:
   - `hands_off` (true/false) — enables auto-provisioning and optional secret persistence
   - `environment` (default: `deploy-approle`) — gating environment for AppRole provisioning

2. **Provisions AppRole** (if `hands_off=true` and `VAULT_ADMIN_TOKEN` present):
   - Runs `scripts/ci/setup-approle.sh` (idempotent)
   - Creates Vault policy, role, and secret ID
   - Outputs `role_id` and `secret_id` as job outputs

3. **Optionally persists credentials** (if `GITHUB_ADMIN_TOKEN` present):
   - Calls `scripts/ci/persist-secret.sh`
   - Stores `VAULT_ROLE_ID` and `VAULT_SECRET_ID` to repo secrets
   - Subsequent runs use persisted secrets (no re-provisioning needed)

4. **Deploys ephemeral runners**:
   - Spins up temporary, configured runners
   - Runners authenticate via Vault AppRole
   - Deploys application artifacts from MinIO
   - Runners automatically terminate after job completion

### Example: Triggering a Hands-Off Deploy

```bash
gh workflow run deploy-rotation-staging.yml \
  --repo kushin77/self-hosted-runner \
  --field hands_off=true \
  --field environment=deploy-approle
```

The workflow will pause at the approval gate (if `deploy-approle` has required reviewers); approvers must review and approve before provisioning proceeds.

---

## Architecture: Immutable, Sovereign, Ephemeral

### Immutable
- All configurations defined in version-controlled YAML (Terraform, workflows, runbooks)
- No manual server state changes; all changes tracked via git
- Rollback capability: revert commits to roll back infrastructure

### Sovereign
- Artifact storage: MinIO (self-hosted, not GitHub artifact hosting)
- Secret management: Vault (not GitHub-only)
- CI runners: Runner containers or VMs fully managed by your infrastructure
- No dependency on GitHub-hosted infrastructure beyond the repository

### Ephemeral
- Runners spun up per deployment, configured from scripts
- Runners terminate automatically after job completion
- No persistent runner state (state stored in Vault, artifacts in MinIO)
- Cost-efficient: pay only for compute during deployments

### Hands-Off
- Manual inputs: paste secrets once, then fully automated
- All provisioning guarded behind environment approval gates
- Audit trail: every deployment tracked in GitHub Actions logs and Vault audit logs
- No human intervention needed after initial setup (optional auto-persistence via `GITHUB_ADMIN_TOKEN`)

---

## File Structure & Key Components

### Workflows
- `.github/workflows/e2e-validate.yml` — One-click E2E validation + guarded dispatch
- `.github/workflows/deploy-immutable-ephemeral.yml` — Main immutable deploy (idempotent, AppRole-gated)
- `.github/workflows/deploy-rotation-staging.yml` — Hands-off staging deploy with optional secret persistence
- `.github/workflows/minio-validate.yml` — MinIO smoke-test (upload/download/verify)
- Other workflows: migrated to MinIO for artifact storage

### Scripts
- `scripts/ci/setup-approle.sh` — Idempotent AppRole provisioning (CLI + HTTP fallback)
- `scripts/ci/deploy-runner-policy.hcl` — Minimal Vault policy for runner auth
- `scripts/ci/check-secrets.sh` — Validates required secrets before running
- `scripts/ci/persist-secret.sh` — Guarded helper to persist secrets via GH API
- `scripts/minio/install-mc.sh` — MinIO client installation
- `scripts/minio/upload.sh` / `download.sh` — Artifact helpers
- `services/pipeline-repair/strategies/retry.js` — Enhanced retry with backoff

### Documentation
- `docs/HANDS_OFF_RUNBOOK.md` — Operational runbook for hands-off deploys
- `docs/DEPLOYMENT_READINESS.md` — This file
- Inline comments in workflow YAML and scripts

### Configuration
- `scripts/ci/deploy-runner-policy.hcl` — Vault policy template

---

## Getting Started: Step-by-Step

### Step 1: Add MinIO Secrets
```bash
gh secret set MINIO_ENDPOINT --body "https://mc.elevatediq.ai:9000" --repo kushin77/self-hosted-runner
gh secret set MINIO_ACCESS_KEY --body "..." --repo kushin77/self-hosted-runner
gh secret set MINIO_SECRET_KEY --body "..." --repo kushin77/self-hosted-runner
gh secret set MINIO_BUCKET --body "github-actions-artifacts" --repo kushin77/self-hosted-runner
```

### Step 2: Configure Approvers on `deploy-approle` Environment
1. GitHub UI: **Settings → Environments → deploy-approle → Required reviewers**
2. Add team or users (e.g., `@your-org/infra-admins`)

### Step 3: (Optional) Add Vault Admin Token for Auto-Provisioning
```bash
gh secret set VAULT_ADMIN_TOKEN --body "s.abc123..." --repo kushin77/self-hosted-runner
```

### Step 4: (Optional) Add GitHub Admin Token for Secret Persistence
```bash
gh secret set GITHUB_ADMIN_TOKEN --body "ghp_..." --repo kushin77/self-hosted-runner
```

### Step 5: Run E2E Validation
```bash
gh workflow run e2e-validate.yml --repo kushin77/self-hosted-runner --field run_deploy=true
```

### Step 6: Monitor & Approve
- Watch the E2E workflow run in GitHub Actions
- When it reaches the approval gate, review and approve (if required)
- E2E workflow dispatches `deploy-rotation-staging` on success
- Monitor `deploy-rotation-staging` run for deployment progress

---

## Troubleshooting

### E2E Workflow Fails at "Validate required secrets"
**Cause**: MinIO secrets are missing.  
**Fix**: Add `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`, `MINIO_BUCKET` to repository secrets.

### MinIO Upload Fails
**Cause**: MinIO endpoint unreachable or credentials invalid.  
**Fix**: 
1. Verify endpoint is correct: `curl -k https://mc.elevatediq.ai:9000`
2. Verify credentials: `mc alias set minio-ci https://mc.elevatediq.ai:9000 AKIA SECRET`
3. Check bucket exists and service account has permissions

### Approval Gate Hangs
**Cause**: `deploy-approle` environment has no required reviewers or all reviewers are unavailable.  
**Fix**: Add approvers to `deploy-approle` in GitHub Settings, or create/update approvers list.

### AppRole Provisioning Fails
**Cause**: `VAULT_ADMIN_TOKEN` is missing, invalid, or doesn't have permission to create AppRoles.  
**Fix**:
1. Verify token is set: `gh secret view VAULT_ADMIN_TOKEN`
2. Verify Vault token policy includes `auth/approle/*` permissions
3. Check Vault server is reachable: `curl $VAULT_ADDR/v1/sys/health`

### Secret Persistence Fails
**Cause**: `GITHUB_ADMIN_TOKEN` missing, invalid, or doesn't have `secrets:write` scope.  
**Fix**:
1. Verify token is set and has `secrets:write` scope
2. Create a new token with minimal scope if needed
3. Check GitHub API is reachable

---

## Monitoring & Audit

### Deployment Logs
All deployments are logged in GitHub Actions:
- **Workflow runs**: https://github.com/kushin77/self-hosted-runner/actions
- **Filter by workflow**: "E2E Validate & Hands-off Deploy", "deploy-rotation-staging"
- **Job logs**: Click workflow run → job name → step logs

### Vault Audit Logs
Every AppRole creation/use is logged in Vault:
```bash
vault audit list  # verify audit backend enabled
vault audit enable file file_path=/vault/logs/audit.log  # if needed
```

### MinIO Audit Logs
MinIO logs all object uploads/downloads (enable in MinIO dashboard or via CLI):
```bash
mc admin trace minio-alias
```

### GitHub Action Logs
All workflow step outputs are visible in GitHub Actions UI. To retrieve programmatically:
```bash
gh run view <run-id> --log
```

---

## Next Steps After Validation

Once E2E passes and the hands-off deploy completes successfully:

1. **Review deployment logs** for any warnings or errors
2. **Verify runners came up**: Check runner registration on your infrastructure
3. **Check artifacts in MinIO**: Verify deployed application artifacts are present
4. **Test runner execution**: Trigger a sample job on a deployed runner
5. **Document team runbook**: Share this runbook with your ops team
6. **Set up alerting**: Configure Prometheus/Grafana to alert on failed deployments
7. **Plan rotation policy**: Define how often to rotate runners (weekly/monthly)

---

## Security Considerations

1. **Vault AppRole Rotation**: AppRoles should be rotated regularly. The helper script (`setup-approle.sh`) supports rotation via idempotent re-provisioning.
2. **MinIO Credentials**: Store credentials in Vault if possible, not just GitHub secrets.
3. **Token Scope**: `GITHUB_ADMIN_TOKEN` should be scoped to minimal permissions (`secrets:write` only).
4. **Audit Retention**: Enable and monitor Vault and MinIO audit logs; retain for compliance period.
5. **Network Isolation**: Vault and MinIO should only be accessible from your self-hosted runners and CI infrastructure.

---

## Support & Issues

For issues or questions:
- Check existing GitHub issues: https://github.com/kushin77/self-hosted-runner/issues
- See #765 (MinIO secrets), #766 (environment setup), #770 (E2E validation)
- Consult runbook: `docs/HANDS_OFF_RUNBOOK.md`
- Review workflow YAML for inline documentation

---

**Last Updated**: March 6, 2026  
**Version**: 1.0 (Initial Release)
