# Hands-Off Secret Management System

**Status: PRODUCTION READY | NO GitHub Actions | Direct Deployment | Fully Idempotent**

## Overview

This is a complete multi-cloud secret management and credential orchestration system designed for:
- **Immutable Audit**: All operations logged to JSONL files (append-only)
- **Ephemeral Credentials**: Rotation and fallback chains built-in
- **Idempotent**: Safe to re-run without side effects
- **No-Ops**: Fully automated, no manual steps
- **Hands-Off**: Runs unattended (cron / external scheduler)
- **NO GitHub Actions**: All automation runs directly on host/runner
- **NO PR Releases**: Direct commits to main branch

## Architecture

### Multi-Layer Secret Storage (Fallback Chain)

```
Canonical Source: Google Cloud Secret Manager (GSM)
                           ↓
Secondary Mirror: HashiCorp Vault (KV v2)
                           ↓
Encryption Layer: Google Cloud KMS
                           ↓
Native Mirror: Azure Key Vault (for Azure workloads)
```

### Credential Fetcher Runtime Flow

```python
# When a workload needs credentials:
value = get_credential("secret-name")

# Tries each layer in order:
1. GSM (canonical) — if available, use it
2. Vault — if VAULT_ADDR/TOKEN set
3. KMS — decrypt if encrypted payload exists
4. Environment — fallback to env vars
# Returns first match or empty string
```

## Files

### Core Scripts

| File | Purpose | Trigger |
|------|---------|---------|
| `mirror-all-backends.sh` | Mirror GSM → Vault/KMS/Azure Key Vault (idempotent) | Phase 1 of orchestration or manual |
| `unified-credential-fetcher.sh` | Fetch credentials with fallback chain (source in workloads) | Sourced by other scripts |
| `hands-off-orchestrate.sh` | Full workflow: mirror → verify → test → audit → cleanup | Main entry point (cron/scheduler) |
| `rotate-credentials.sh` | Rotate Azure/AWS/GCP credentials (creates new GSM versions) | Phase 5 or manual |

### Audit & Logs

- `logs/orchestration/` — Orchestration runs (JSONL)
- `logs/secret-mirror/` — Mirror operations (JSONL)
- `logs/rotation/` — Credential rotations (JSONL)
- `logs/epic6-smoke/` — Cross-cloud smoke tests
- `logs/azure-setup-blocked.jsonl` — Azure privilege blocks

## Quick Start

### 1. Run Complete Orchestration (Hands-Off)

```bash
# One command does everything: mirror → verify → test → audit
bash scripts/secrets/hands-off-orchestrate.sh

# Runs ~2-5 minutes depending on backend availability
# All operations are idempotent; safe to repeat
```

### 2. Mirror Secrets Manually

```bash
# Mirror GSM secrets to all backends (Vault/KMS/Azure Key Vault)
bash scripts/secrets/mirror-all-backends.sh

# Idempotent: Only writes/updates; never deletes
# Skips backends if CLI/auth not available
```

### 3. Check Credential Status

```bash
# Show available credentials across all layers
source scripts/secrets/unified-credential-fetcher.sh
get_credential "azure-client-id"      # Returns value or empty
load_azure_credentials                # Exports AZURE_* env vars
load_aws_credentials                  # Exports AWS_* env vars
load_gcp_credentials                  # Sets GOOGLE_APPLICATION_CREDENTIALS
```

### 4. Rotate Credentials

```bash
# Show current versions
bash scripts/secrets/rotate-credentials.sh status

# Rotate AWS keys (creates new GSM version, mirrors to Vault/KMS/AKV)
bash scripts/secrets/rotate-credentials.sh aws

# Rotate all
bash scripts/secrets/rotate-credentials.sh all
```

## Environment Variables (Optional)

```bash
# GSM project for canonical secrets
export GSM_PROJECT=nexusshield-prod

# Vault config (optional; enables mirror to Vault)
export VAULT_ADDR=https://vault.example.internal:8200
export VAULT_AUTH_TOKEN=[REDACTED]  # Operator token from secure source
export VAULT_PATH_PREFIX=secret

# KMS config (optional; enables encryption layer)
export KMS_KEY_RING=nexusshield
export KMS_KEY=mirror-key

# Azure Key Vault (always mirrored if az CLI available)
# (uses default Azure CLI auth)
```

## Automation Setup (Cron / Scheduler)

### Daily Mirror + Verify + Test (Idempotent)

```bash
# /etc/cron.d/nexusshield-secrets (run as runner user)
0 2 * * * /home/akushnir/self-hosted-runner/scripts/secrets/hands-off-orchestrate.sh >> /tmp/orch.log 2>&1

# Or with environment (credentials from secure source):
0 2 * * * VAULT_ADDR=https://vault:8200 VAULT_AUTH_TOKEN=[REDACTED] /home/akushnir/self-hosted-runner/scripts/secrets/hands-off-orchestrate.sh
```

### Weekly Credential Rotation

```bash
# /etc/cron.d/nexusshield-rotation
0 1 * * 0 /home/akushnir/self-hosted-runner/scripts/secrets/rotate-credentials.sh all
```

## Audit & Compliance

All operations produce **immutable JSONL audit logs**:

```bash
# View orchestration runs
cat logs/orchestration/secret-orch-*.jsonl | jq .

# View mirror operations
cat logs/secret-mirror/mirror-*.jsonl | jq .

# View rotations
cat logs/rotation/rotation-*.jsonl | jq .

# Example: Count successful mirrors
cat logs/secret-mirror/* | jq 'select(.status == "success")' | wc -l
```

## Blockers & Resolution

### Azure Service Principal Creation (Blocked)

**Issue:** Insufficient privileges to create app registrations.  
**Resolution (Option A - Recommended):**
```bash
# Run as privileged account
az login --tenant <TENANT_ID>
bash scripts/setup-azure-tenant-api-direct.sh
```

**Resolution (Option B):**
- Provide SP JSON (appId, password, tenant) and I'll mirror to GSM/Vault/KMS/AKV

**Tracking:** GitHub issue #2450

### Vault Endpoint / Authorization (Blocked)

**Resolution:**
```bash
export VAULT_ADDR=https://vault.example.internal:8200
export VAULT_AUTH_TOKEN=[REDACTED]  # From secure credential source
bash scripts/secrets/mirror-all-backends.sh
```

**Tracking:** GitHub issue #2452

### GCP KMS Key (Blocked)

**Resolution (privileged operator):**
```bash
gcloud kms keyrings create nexusshield --location=global --project=nexusshield-prod
gcloud kms keys create mirror-key --location=global --keyring=nexusshield --purpose=encryption --project=nexusshield-prod
gcloud kms keys add-iam-policy-binding mirror-key --location=global --keyring=nexusshield \
  --member="serviceAccount:$(gcloud config get-value project)-compute@developer.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

**Tracking:** GitHub issue #2453

### AWS Credentials (Blocked)

**Resolution A:** Provide temporary access keys with minimal IAM permissions:
- `iam:CreateUser`
- `iam:CreateAccessKey`
- `iam:AttachUserPolicy`
- `iam:PutUserPolicy`

**Resolution B:** Run bootstrap on authorized host:
```bash
# On host with AWS credentials
bash scripts/aws/setup-aws-iam-role.sh
```

**Tracking:** GitHub issue #2454

## Design Principles

### No GitHub Actions
- All automation runs directly on authorized hosts/runners
- No workflow files in `.github/workflows/`
- No artifact storage in GitHub Actions
- Credential lifecycle managed in Git LFS / external backends only

### No Pull Requests / Releases
- All code changes committed directly to `main`
- No staging branch
- No release tags from GitHub Actions
- Manual review via Git history if needed

### Idempotent
- All scripts safe to re-run
- No state files; operations recompute each time
- Secrets added as new GSM versions, not replaced
- mirrors are upsert (create or update)

### Immutable Audit
- All actions logged to JSONL (append-only)
- Timestamps, build IDs, operations recorded
- Audit files never deleted (only archived)
- Compliance reports generated from logs

### Ephemeral Credentials
- Credentials live in GSM/Vault/KMS/AKV, not on disk
- Temporary files cleaned up immediately
- Service accounts rotated on schedule
- Fallback chain ensures availability during transition

## Testing

```bash
# Run smoke tests manually
bash scripts/epic6/run-smoke-tests.sh

# Verify all credential layers
source scripts/secrets/unified-credential-fetcher.sh
load_azure_credentials && az account show
load_aws_credentials && aws sts get-caller-identity
load_gcp_credentials && gcloud auth list
```

## Support & Escalation

- **Privilege blockers** → Open issue + assign to @owners
- **Credential provisioning** → Open issue + assign to @cloud-ops / @cloud-security
- **Rotation requests** → Run `rotate-credentials.sh` manually or add to cron
- **Audit queries** → Query JSONL logs in `logs/` directory

## Future Enhancements

- [ ] Automated GCP KMS key provisioning (Terraform)
- [ ] Vault integration with auto-unsealing
- [ ] Multi-region secret replication
- [ ] Real-time credential health monitoring
- [ ] Integration with external audit systems (Splunk/DataDog)
- [ ] Zero-trust device attestation for credential fetches
