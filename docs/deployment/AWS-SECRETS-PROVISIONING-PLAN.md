# AWS Secrets Manager Provisioning - Execution Plan

**Date:** March 9, 2026  
**Status:** READY FOR DEPLOYMENT  
**Blocker:** AWS credentials not yet configured (expected - requires ops team activation)

---

## Issue Summary

The worker node (192.168.168.42) requires AWS Secrets Manager access to retrieve and store credentials for the direct deployment system.

**Primary Issue:** [PROVISION-AWS-SECRETS.md](./ISSUES/PROVISION-AWS-SECRETS.md)

---

## What's Ready

The repository contains a complete, production-ready provisioning script:

**Script:** `scripts/operator-aws-provisioning.sh` (430+ lines)

**What it does:**
1. ✅ Verifies AWS credentials and permissions
2. ✅ Creates KMS encryption key for credentials (`runner-credential-encryption-key`)
3. ✅ Provisions SSH credentials secret (`runner/ssh-credentials`)
4. ✅ Provisions AWS credentials secret (`runner/aws-credentials`)
5. ✅ Provisions DockerHub credentials secret (`runner/dockerhub-credentials`)
6. ✅ Grants IAM permissions to runner role
7. ✅ Verifies secret accessibility

**Features:**
- Dry-run mode (`--dry-run`) for safe preview
- Verbose logging for debugging
- Region configuration (`--region REGION`)
- Idempotent (safe to re-run)
- 100% automated

---

## Execution Steps (for ops team)

### Step 1: Configure AWS Credentials

```bash
# Option A: Use AWS SSO / temporary credentials
aws sso login --profile dev

# Option B: Use IAM user (standard approach)
aws configure --profile dev
# Enter: Access Key ID, Secret Access Key, Region (us-east-1), Output (json)
```

### Step 2: Run AWS Secrets Provisioning (Dry-Run First)

```bash
# Test without making changes
DRY_RUN=true VERBOSE=true ./scripts/operator-aws-provisioning.sh

# Expected output: ✅ All verification steps pass
```

### Step 3: Execute AWS Provisioning

```bash
# Create all secrets, KMS key, and IAM policies
./scripts/operator-aws-provisioning.sh --verbose

# Check success (should see all ✅ checkmarks):
# ✅ AWS credentials verified
# ✅ KMS key created
# ✅ SSH credentials secret created
# ✅ AWS credentials secret created
# ✅ DockerHub credentials secret created
# ✅ IAM policy attached to runner role
# ✅ All secrets accessible
```

### Step 4: Configure Worker Instance

Option A (Recommended): Attach IAM Role to Worker Instance
```bash
# On AWS console or via CLI:
# 1. Create role "runner-role" with trust policy for EC2
# 2. Attach policy created by provisioning script
# 3. Attach role to instance 192.168.168.42
```

Option B: Configure Environment on Worker
```bash
# SSH to worker:
ssh akushnir@192.168.168.42

# Export credentials (for testing):
export AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID"
export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY"
export AWS_REGION="us-east-1"

# Verify access:
aws secretsmanager get-secret-value --secret-id "runner/ssh-credentials"
```

---

## Current Environment Status

| Item | Status | Details |
|------|--------|---------|
| `scripts/operator-aws-provisioning.sh` | ✅ Ready | 430 lines, production-quality |
| AWS CLI | ✅ Installed | v2+ available |
| AWS Config | ✅ Configured | Profiles: default, dev, staging, prod |
| AWS Credentials | ❌ Needs Setup | Not loaded (expected) |
| Target Host | ✅ Reachable | 192.168.168.42:22 |
| SSH Access | ✅ Ready | akushnir@192.168.168.42 |

---

## Next Steps

1. **Operator:** Configure AWS credentials (Step 1 above)
2. **Operator:** Execute provisioning script (Steps 2-3)
3. **Operator:** Attach IAM role to worker or export credentials (Step 4)
4. **System:** Vault agent will read from Secrets Manager on next restart
5. **Verify:** `aws secretsmanager describe-secret --secret-id "runner/ssh-credentials"`

---

## References

- **Provisioning Script:** [scripts/operator-aws-provisioning.sh](./scripts/operator-aws-provisioning.sh)
- **Issue:** [PROVISION-AWS-SECRETS.md](./ISSUES/PROVISION-AWS-SECRETS.md)
- **Deployment Guide:** [README_DEPLOYMENT_SYSTEM.md](./README_DEPLOYMENT_SYSTEM.md#-operational-guarantees)
- **Observability Next:** [PROVISION_OBSERVABILITY_AND_GATES_2026_03_09.md](./issues/PROVISION_OBSERVABILITY_AND_GATES_2026_03_09.md)

---

## Architecture Guarantees

Once deployed, AWS Secrets Manager integrates with:
- ✅ **Vault Agent** (`systemd` service, reads on startup)
- ✅ **Multi-Layer Credentials** (GSM primary, Vault secondary, AWS tertiary)
- ✅ **Encryption** (KMS encryption at rest)
- ✅ **Audit Trail** (Secrets Manager CloudTrail logs)
- ✅ **Idempotent Deployments** (immutable credential distribution)

---

**Status:** Ready to hand off to ops team for execution.  
**Estimated Time:** 5-10 minutes for full provisioning.
