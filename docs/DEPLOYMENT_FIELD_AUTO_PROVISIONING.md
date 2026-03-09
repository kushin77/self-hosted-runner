# 🚀 Deployment Field Auto-Provisioning System

**Status:** ✅ Implemented & Ready for Use  
**Date:** 2026-03-09  
**Component:** Immutable, Ephemeral, Idempotent, No-Ops Auto-Provisioning

---

## Overview

This system automatically provisions 4 critical deployment fields during deployment without manual operator intervention. It's designed to be:

- **Immutable** - All operations recorded in audit trail (append-only)
- **Ephemeral** - Lock files auto-clean on completion
- **Idempotent** - Safe to run multiple times
- **No-ops** - Fully automated, zero manual intervention
- **Hands-off** - Uses GSM/Vault/KMS for credential sourcing

---

## Required Deployment Fields

| Field | Purpose | Format | Example |
|-------|---------|--------|---------|
| **VAULT_ADDR** | HashiCorp Vault server URL | URL | https://vault.company.com:8200 |
| **VAULT_ROLE** | Vault role for GitHub Actions | String | github-actions-prod |
| **AWS_ROLE_TO_ASSUME** | AWS IAM role for OIDC federation | ARN | arn:aws:iam::987654321098:role/github-actions |
| **GCP_WORKLOAD_IDENTITY_PROVIDER** | GCP Workload Identity Federation provider | Resource path | projects/my-project/locations/global/workloadIdentityPools/github/providers/github |

---

## Components

### 1. **auto-provision-deployment-fields.sh** (Main Provisioning Engine)

Automatically populates all 4 fields from credential providers with fallback logic.

```bash
# Standard execution (discovers from any provider)
./scripts/auto-provision-deployment-fields.sh

# Prefer GSM as primary provider
PREFERRED_PROVIDER=gsm ./scripts/auto-provision-deployment-fields.sh

# Dry-run mode (no changes, just discoveries)
./scripts/auto-provision-deployment-fields.sh --dry-run

# Force override (bypasses 30s lock timeout)
FORCE=true ./scripts/auto-provision-deployment-fields.sh
```

**Features:**
- Multi-provider support (GSM → Vault → KMS fallback)
- Idempotent lock file mechanism
- Immutable audit trail in `logs/deployment-provisioning-audit.jsonl`
- Provisions to 3 targets:
  1. GitHub Actions repository secrets
  2. Environment variables file (`.env.deployment`)
  3. Systemd daemon environment (if available)
- Automatic verification post-provisioning

### 2. **discover-deployment-fields.sh** (Field Discovery)

Discovers current state of all 4 deployment fields across the system.

```bash
# Text report (human-friendly)
./scripts/discover-deployment-fields.sh

# JSON output (for parsing)
./scripts/discover-deployment-fields.sh json

# Markdown report (for documentation)
./scripts/discover-deployment-fields.sh markdown
```

**Output Includes:**
- Current value & source
- Placeholder detection
- Number of references in codebase
- Action required suggestions

### 3. **verify-deployment-provisioning.sh** (Comprehensive Verification)

Validates all fields are properly provisioned and providers are accessible.

```bash
# Standard verification
./scripts/verify-deployment-provisioning.sh

# Verbose output (for debugging)
./scripts/verify-deployment-provisioning.sh --verbose

# In GitHub Actions (auto-detects credentials)
./scripts/verify-deployment-provisioning.sh
```

**Tests:**
- All fields are set
- No placeholder values remain
- Vault server is reachable and unsealed
- Vault role is properly named
- AWS IAM role ARN format is valid
- GCP WIF provider format is valid
- All credential providers are accessible

---

## Credential Provider Architecture

### Priority Order (Automatic Fallback)

```
1. Google Secret Manager (GSM)
   └─ Requires: gcloud CLI + authentication
   └─ Secret path: deployment-fields-{FIELD_NAME}

2. HashiCorp Vault
   └─ Requires: vault CLI + VAULT_TOKEN or VAULT_ROLE
   └─ Secret path: secret/deployment/fields/{FIELD_NAME}

3. AWS Secrets Manager + KMS
   └─ Requires: aws CLI + IAM credentials
   └─ Secret path: deployment/{FIELD_NAME}
```

### Environment Variables

```bash
# Credential provider preference
PREFERRED_PROVIDER=gsm|vault|kms

# Vault configuration
VAULT_ADDR=https://vault.example.com:8200
VAULT_TOKEN=hvs.xxxxx (or use VAULT_ROLE for AppRole)
VAULT_ROLE=github-actions-role

# GSM configuration
GCP_PROJECT_ID=my-project

# AWS configuration
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=987654321098
```

---

## Integration Points

### 1. GitHub Actions Workflow

```yaml
name: Deploy with Auto-Provisioning

on: workflow_dispatch

jobs:
  provision:
    runs-on: self-hosted
    steps:
      # Discover current state
      - name: Discover deployment fields
        run: ./scripts/discover-deployment-fields.sh markdown

      # Auto-provision all fields
      - name: Auto-provision deployment fields
        env:
          PREFERRED_PROVIDER: gsm
        run: ./scripts/auto-provision-deployment-fields.sh

      # Verify provisioning succeeded
      - name: Verify provisioning
        run: ./scripts/verify-deployment-provisioning.sh --verbose
```

### 2. Manual Deployment Script

```bash
#!/bin/bash
set -e

# Discover current state
echo "Discovering deployment fields..."
./scripts/discover-deployment-fields.sh

# Auto-provision
echo "Provisioning deployment fields..."
./scripts/auto-provision-deployment-fields.sh

# Verify
echo "Verifying provisioning..."
./scripts/verify-deployment-provisioning.sh

# Continue with deployment
echo "All fields provisioned, proceeding with deployment..."
make deploy
```

### 3. Systemd Service

```ini
# /etc/systemd/system/deployment-provisioner.service

[Unit]
Description=Deployment Field Auto-Provisioner
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=akushnir
ExecStart=/path/to/scripts/auto-provision-deployment-fields.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Or as a timer:

```ini
# /etc/systemd/system/deployment-provisioner.timer

[Unit]
Description=Auto-Provision Deployment Fields Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
```

---

## Operational Procedures

### Initial Setup

**Step 1: Prepare Credential Provider Secrets**

Ensure your credential provider has the 4 secrets configured:

**Google Secret Manager:**
```bash
echo "https://vault.company.com:8200" | \
  gcloud secrets versions add deployment-fields-VAULT_ADDR --data-file=-

echo "github-actions-prod" | \
  gcloud secrets versions add deployment-fields-VAULT_ROLE --data-file=-

# ... etc for AWS and GCP fields
```

**HashiCorp Vault:**
```bash
vault kv put secret/deployment/fields/VAULT_ADDR value=https://vault.company.com:8200
vault kv put secret/deployment/fields/VAULT_ROLE value=github-actions-prod

# ... etc
```

**Step 2: Run Auto-Provisioning**

```bash
export PREFERRED_PROVIDER=gsm  # or vault, kms
./scripts/auto-provision-deployment-fields.sh
```

**Step 3: Verify Provisioning**

```bash
./scripts/verify-deployment-provisioning.sh

# Expected output:
# ✅ All deployment fields are properly configured!
```

### Monitoring & Auditing

**View Provisioning Audit Trail:**

```bash
# All provisioning events
tail -f logs/deployment-provisioning-audit.jsonl

# Specific field
grep "VAULT_ADDR" logs/deployment-provisioning-audit.jsonl | python3 -m json.tool

# Failures only
grep '"status":"failed"' logs/deployment-provisioning-audit.jsonl
```

**Example Audit Entry:**
```json
{
  "timestamp": "2026-03-09T05:45:00Z",
  "action": "fetch",
  "field": "VAULT_ADDR",
  "status": "success",
  "source": "gsm",
  "hostname": "prod-runner-01",
  "user": "akushnir"
}
```

### Troubleshooting

#### Issue: "Failed to fetch field from any provider"

**Solution:**
1. Verify credential provider is accessible
2. Check secret exists in provider
3. Verify authentication credentials
4. Run discovery to see current state:
   ```bash
   ./scripts/discover-deployment-fields.sh --verbose
   ```

#### Issue: "Lock file exists after timeout"

**Solution:**
1. Check if another provisioning is running: `ps aux | grep auto-provision`
2. Override with force flag if needed: `FORCE=true ./scripts/auto-provision-deployment-fields.sh`
3. Or wait for current provisioning to complete

#### Issue: "Still contains placeholder value"

**Solution:**
1. Verify credential provider has actual value (not placeholder)
2. Check that value doesn't match pattern: `example.com`, `placeholder`, `YOUR_`, etc.
3. Update credential provider secret and re-run provisioning

#### Issue: "Cannot reach Vault at VAULT_ADDR"

**Solution:**
1. Test connectivity: `curl -I https://vault.company.com:8200/v1/sys/health`
2. Check firewall rules allow outbound HTTPS
3. Verify VAULT_ADDR URL is correct
4. Ensure Vault is unsealed: `curl https://vault.company.com:8200/v1/sys/health | jq .sealed`

---

## Security Considerations

### Secrets in Transit

- All credential fetching uses HTTPS with certificate validation
- Environment variables containing secrets are kept in memory only
- GitHub Actions secrets are encrypted at rest by GitHub
- Systemd environment is restricted to service processes

### Audit Trail

- Immutable append-only log (cannot be deleted)
- SHA-256 hash of previous entry for chain integrity
- Records timestamp, field, action, source, hostname, user
- Retained for 365 days minimum

### Access Control

- Lock file prevents concurrent modification
- Systemd drop-in requires sudo to modify
- Audit trail is read-only after creation
- All operations logged and timestamped

---

## Deployment Integration

### Recommended Workflow

```
1. Pre-deployment discovery
   └─ ./scripts/discover-deployment-fields.sh markdown

2. Auto-provision all fields
   └─ ./scripts/auto-provision-deployment-fields.sh

3. Verify provisioning succeeded
   └─ ./scripts/verify-deployment-provisioning.sh

4. Proceed with deployment
   └─ make deploy

5. Post-deployment audit
   └─ tail logs/deployment-provisioning-audit.jsonl
```

### High Availability Setup

For multi-instance deployments:

1. **Primary provisioning** runs on master
2. **Replication** to standby via `rsync` or git commit
3. **Verification** runs on each instance before using fields
4. **Audit synchronization** via central log aggregation

---

## References

- [Daemon Scheduler Guide](DAEMON_SCHEDULER_GUIDE.md) - Uses provisioned fields
- [Phase 2 Activation Guide](PHASE2_ACTIVATION_GUIDE.md) - Initial setup
- [On-call Reference](ON_CALL_QUICK_REFERENCE.md) - Emergency procedures
- [GitHub Issues](https://github.com/kushin77/self-hosted-runner/issues/2070) - Track provisioning work

---

## FAQ

**Q: What if a field is still a placeholder after provisioning?**
A: The credential provider doesn't have the actual value. Add it to your GSM/Vault/KMS, then re-run provisioning.

**Q: Can I use multiple credential providers simultaneously?**
A: Yes, the system tries all providers in order and uses the first successful one.

**Q: How often should provisioning run?**
A: On each deployment. Can also run hourly via systemd timer for continuous validation.

**Q: What happens if provisioning partially fails?**
A: It continues provisioning remaining fields and records failures in audit trail. Verification will report what failed.

**Q: Are the secrets stored in git?**
A: Never. Secrets are only in credential providers (GSM/Vault/KMS) and GitHub Actions secrets.

---

**Last Updated:** 2026-03-09  
**Version:** 1.0  
**Status:** Production Ready ✅
