# Credential Rotation Operations Playbook
**Status**: Production-Ready Hands-Off Automation  
**Date**: March 12, 2026  
**Owner**: Platform Operations (hands-off automated)

---

## Executive Summary
This document describes the fully-automated, hands-off credential rotation system using:
- **GSM** (Google Secret Manager) for ephemeral secret versioning
- **Vault** (HashiCorp) for AppRole secret_id rotation
- **AWS KMS** for AWS credential encryption
- **Cloud Build** for orchestration (no GitHub Actions)
- **Direct Deployment** (no release gates, no PR approvals)

## Credentials Managed

| Secret | Rotation Interval | Storage | Ephemeral TTL | Status |
|--------|-----------------|---------|--------------|--------|
| `github-token` | Per rotation run | GSM | N/A (GH token) | ✅ Automated |
| `aws-access-key-id` | Per rotation run | GSM | N/A (AWS key) | ✅ Automated |
| `aws-secret-access-key` | Per rotation run | GSM | N/A (AWS secret) | ✅ Automated |
| `vault-example-role-secret_id` | Per rotation run | GSM | AppRole TTL (Vault-enforced) | ⏳ Waiting for Vault creds |

## Architecture

### Immutable (WORM Storage)
- All rotated secrets stored as new versions in GSM (versioning is immutable)
- Rotation audit logged to `logs/rotation-audit-*.jsonl` (append-only)
- No secret overwrite; only new versions created

### Idempotent
- `scripts/secrets/rotate-credentials.sh` is safe to re-run:
  - Checks if secret exists, creates if missing
  - Adds new version if secret differs from current latest
  - Logs all actions per rotation run
- Cloud Build job can be re-triggered without side effects

### Ephemeral & No-Ops
- Vault AppRole secret_id enforced with TTL (Vault-side)
- AWS credentials minimal-permission (uses specific service account)
- GitHub tokens scoped to specific repos/permissions
- All credential provisioning automated; no manual secret creation allowed

### Hands-Off Automated
- **Trigger**: Cloud Build job via `gcloud builds submit`
- **Schedule**: Can be placed in Cloud Scheduler for periodic rotation (recommended: weekly)
- **Self-Contained**: Fetches secrets from GSM, rotates, stores new versions, logs audit entry
- **No approval gates**: Direct deployment of secrets once rotated (no PR review needed)

---

## Credential Sources

### Google Secret Manager Secrets (GSM Project: `nexusshield-prod`)

All secrets provisioned in GSM with versioning. Rotation agent reads latest version, performs rotation, and stores new version.

**Required Secrets**:
1. `github-token` — GitHub personal access token (read/write to repos)
2. `aws-access-key-id` — AWS IAM access key ID
3. `aws-secret-access-key` — AWS IAM secret access key
4. `VAULT_ADDR` — Vault server URL (e.g., `https://vault.example.com`)
5. `VAULT_TOKEN` — Vault admin/service token for AppRole rotation

---

## Rotation Workflow

### Entry Point: Cloud Build Job

```bash
gcloud builds submit --config=cloudbuild/run-vault-rotation.yaml \
  --substitutions=_GSM_PROJECT=nexusshield-prod \
  --project=nexusshield-prod
```

### Step 1: Fetch Rotation Script
```bash
git clone https://github.com/kushin77/self-hosted-runner.git repo
cd repo
bash scripts/secrets/run_vault_rotation.sh
```

### Step 2: Rotation Script Actions
The script `scripts/secrets/run_vault_rotation.sh`:

1. **Detects** real vs. placeholder secrets (fails fast on placeholder Vault creds)
2. **Validates** Vault health (curl to `/v1/sys/health`)
3. **Requests** new AppRole secret_id from Vault
4. **Stores** new secret_id as new version in GSM `vault-example-role-secret_id`
5. **Logs** audit entry to `logs/rotation-audit-<timestamp>.jsonl`

### Step 3: Integration with Full Rotation
(Earlier Cloud Build config `cloudbuild/rotate-credentials-cloudbuild.yaml` runs full rotation including GitHub+AWS+Vault)

```bash
gcloud builds submit --config=cloudbuild/rotate-credentials-cloudbuild.yaml \
  --substitutions=PROJECT_ID=nexusshield-prod,_REPO_OWNER=kushin77,_REPO_NAME=self-hosted-runner,_BRANCH=main \
  --project=nexusshield-prod
```

This runs `scripts/secrets/rotate-credentials.sh all` which:
- Rotates GitHub token into GSM
- Rotates AWS credentials into GSM
- Rotates Vault AppRole secret_id into GSM

---

## Automation & Scheduling

### Option 1: Manual Trigger (Testing)
```bash
gcloud builds submit --config=cloudbuild/rotate-credentials-cloudbuild.yaml \
  --substitutions=PROJECT_ID=nexusshield-prod,_REPO_OWNER=kushin77,_REPO_NAME=self-hosted-runner,_BRANCH=main
```

### Option 2: Cloud Scheduler (Production Recommended)
Create a Cloud Scheduler job to run weekly credential rotation:

```bash
gcloud scheduler jobs create http rotate-credentials --schedule="0 2 * * 0" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/nexusshield-prod/builds" \
  --http-method=POST \
  --message-body='{
    "source": {"repoSource": {"repoName": "github_kushin77_self-hosted-runner", "branchName": "main"}},
    "steps": [{
      "name": "gcr.io/cloud-builders/git",
      "args": ["clone", "https://github.com/kushin77/self-hosted-runner.git", "repo"]
    }, {
      "name": "gcr.io/cloud-builders/gcloud",
      "entrypoint": "bash",
      "args": ["-c", "cd repo && gcloud builds submit --config=cloudbuild/rotate-credentials-cloudbuild.yaml --substitutions=PROJECT_ID=nexusshield-prod,_REPO_OWNER=kushin77,_REPO_NAME=self-hosted-runner,_BRANCH=main"]
    }],
    "substitutions": {"PROJECT_ID": "nexusshield-prod"}
  }' \
  --project=nexusshield-prod
```

### Option 3: GitHub Issues Automation (If using GitHub)
Close issue #2851 once all secrets provisioned; automation runs via Cloud Build (no GitHub Actions).

---

## Security Posture

### Immutability ✅
- Secrets stored as GSM versions (version history immutable)
- Rotation audit log is append-only JSON
- No secret modification; only append new versions

### Ephemeralness ✅
- Vault AppRole secret_id subject to TTL (enforced by Vault)
- AWS credentials have minimal IAM permissions
- GitHub tokens scoped to specific repos and operations
- All credentials fetched from GSM at rotation time; not cached in repo

### No-Ops ✅
- Cloud Build orchestrates rotation (managed service)
- No manual intervention required (fully automated)
- Self-healing: if a rotation step fails, build logs are retained; re-trigger via Cloud Build

### Idempotency ✅
- Rotation script checks current state before creating new version
- Re-running rotation job is safe (will create new version if changed)
- No duplicate credentials with same value

### Hands-Off ✅
- No GitHub Actions pipelines
- No release approval workflows
- No pull requests for secret rotation
- Direct commit to main, direct Cloud Build execution

---

## Monitoring & Audit

### Audit Log
Every rotation creates an entry in `logs/rotation-audit-<timestamp>.jsonl`:
```json
{
  "timestamp": "2026-03-12T22:30:15Z",
  "action": "vault_rotation",
  "status": "skipped",
  "reason": "VAULT_ADDR is placeholder",
  "details": {"secrets": ["vault-example-role-secret_id"]}
}
```

### GSM Version History
Check latest versions via `gcloud secrets versions list`:
```bash
gcloud secrets versions list github-token --project=nexusshield-prod
gcloud secrets versions list aws-access-key-id --project=nexusshield-prod
gcloud secrets versions list aws-secret-access-key --project=nexusshield-prod
gcloud secrets versions list vault-example-role-secret_id --project=nexusshield-prod
```

### Cloud Build Logs
All rotation builds logged in Cloud Build; view via:
```bash
gcloud builds list --project=nexusshield-prod --filter="substitutions.PROJECT_ID:*" --limit=20
gcloud builds log <BUILD_ID> --project=nexusshield-prod
```

---

## Troubleshooting

### Issue: Vault Rotation Fails with "Could not resolve host: PLACEHOLDER"
**Cause**: `VAULT_ADDR` or `VAULT_TOKEN` in GSM contains placeholder text  
**Resolution**:
```bash
# Provision real Vault endpoint and token
echo -n "https://your-vault.example.com" | gcloud secrets create VAULT_ADDR --data-file=- --project=nexusshield-prod || gcloud secrets versions add VAULT_ADDR --data-file=- --project=nexusshield-prod
echo -n "s.xxxxxx" | gcloud secrets create VAULT_TOKEN --data-file=- --project=nexusshield-prod || gcloud secrets versions add VAULT_TOKEN --data-file=- --project=nexusshield-prod
# Re-trigger Cloud Build rotation
gcloud builds submit --config=cloudbuild/run-vault-rotation.yaml --substitutions=_GSM_PROJECT=nexusshield-prod
```

### Issue: Cloud Build Permission Denied on Secret Access
**Cause**: Cloud Build SA does not have `roles/secretmanager.secretAccessor` on the secret  
**Resolution**:
```bash
PROJECT=nexusshield-prod
BUILD_SA="$(gcloud projects describe $PROJECT --format='value(projectNumber)')@cloudbuild.gserviceaccount.com"
gcloud secrets add-iam-policy-binding <SECRET_NAME> --project=$PROJECT --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAccessor
```

### Issue: Rotation Creates Duplicate Versions
**Cause**: Script is idempotent and creates new version only if value differs  
**Resolution**: This is expected behavior. Check audit log to verify the new credential value matches expected format.

---

## IAM Requirements

### Cloud Build Service Account
- `roles/secretmanager.secretAccessor` on all credential secrets (read)
- `roles/secretmanager.secretAdmin` on `vault-example-role-secret_id` (write/version)

Grant all at once:
```bash
PROJECT=nexusshield-prod
BUILD_SA="$(gcloud projects describe $PROJECT --format='value(projectNumber)')@cloudbuild.gserviceaccount.com"

for secret in github-token aws-access-key-id aws-secret-access-key VAULT_ADDR VAULT_TOKEN; do
  gcloud secrets add-iam-policy-binding "$secret" --project=$PROJECT \
    --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAccessor
done

gcloud secrets add-iam-policy-binding vault-example-role-secret_id --project=$PROJECT \
  --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAdmin
```

---

## Files & Locations

| File | Purpose |
|------|---------|
| `scripts/secrets/rotate-credentials.sh` | Main rotation orchestrator (all/github/vault/aws) |
| `scripts/secrets/run_vault_rotation.sh` | Vault AppRole secret_id rotation (safe abort on placeholders) |
| `cloudbuild/rotate-credentials-cloudbuild.yaml` | Cloud Build config for full rotation (github+aws+vault) |
| `cloudbuild/run-vault-rotation.yaml` | Cloud Build config for Vault-only rotation |
| `ops/VAULT_ROTATION_README.md` | Vault rotation setup and run instructions |
| `logs/rotation-audit-*.jsonl` | Immutable rotation audit trail |
| `logs/rotate-vault.log` | Vault rotation build log |

---

## Constraints & Compliance

✅ **No GitHub Actions** — Only Cloud Build for orchestration  
✅ **No Release Workflows** — Direct deployment on merge to main  
✅ **No Pull Request Gates** — Rotation commits direct to main  
✅ **Immutable Secrets** — GSM versions are WORM (write-once-read-many)  
✅ **Ephemeral Credentials** — Vault TTLs enforced; AWS keys minimal scope  
✅ **Idempotent** — Safe to re-run rotation at any time  
✅ **Hands-Off** — Fully automated; no manual secret rotation  
✅ **GSM/Vault/KMS** — All credentials stored in GSM (encrypted at rest)  

---

## Next Steps (Operator Actions)

1. **Provision Real Vault Credentials**: Update `VAULT_ADDR` and `VAULT_TOKEN` in GSM (see Troubleshooting section)
2. **Set Up Cloud Scheduler** (optional): Create weekly rotation job for production SLA
3. **Validate Downstream Consumers**: Confirm Cloud Run services and other consumers can read rotated secrets
4. **Close Issue #2851**: Mark as complete once Vault creds provisioned and first full rotation succeeds

---

## References
- [Google Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [Cloud Build Schedule Documentation](https://cloud.google.com/cloud-build/docs/automating-builds/create-managed-scheduled-builds)
- [HashiCorp Vault AppRole Auth](https://developer.hashicorp.com/vault/docs/auth/approle)
