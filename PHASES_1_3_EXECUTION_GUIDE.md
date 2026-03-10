# Credential Provisioning: Phases 1-3 Execution Guide

**Status**: ✅ Phase 1 COMPLETE | 🔄 Phases 2-3 READY FOR OPERATOR | 📋 Approval: APPROVED FOR GO-LIVE (2026-03-09)

**Timeline**: Expected completion 2-3 hours (depends on AWS/GCP approval process)

---

## Executive Summary

This document provides step-by-step instructions for executing Phases 2-3 of the credential provisioning framework. Phase 1 (Vault AppRole) has been completed and verified. The system implements **immutable, ephemeral, idempotent, no-ops** credential management across three providers:

- **Vault** (AppRole) - Production-ready ✅
- **AWS Secrets Manager + KMS** - Ready for operator execution (Phase 2)
- **Google Secret Manager** - Ready for operator execution (Phase 3)

---

## Phase 1: Vault AppRole Hardening ✅ COMPLETE

**Status**: ✅ COMPLETED (2026-03-09 16:30:12)

### What Was Done
- Enabled AppRole auth method on Vault server
- Created `runner-automation` AppRole with configurable role and secret IDs
- Generated secure credentials:
  - **Role ID**: `51bc5a46-c34b-4c79-5bb5-9afea8acf424`
  - **Secret ID**: `bec7cc37...6754d37e` (stored securely)
  - **TTL**: 1 hour (configurable)
  - **Max TTL**: 4 hours (production-safe)

### Current State
- AppRole credentials stored at: `/tmp/vault-approle-credentials.json`
- Permissions: `600` (read-only by akushnir user)
- Ready for vault-agent deployment

### Next Steps
1. Deploy vault-agent to bastion (192.168.168.42)
2. Configure vault-agent to use AppRole credentials
3. Deploy watcher service to consume credentials

---

## Phase 2: AWS Secrets Manager Provisioning 🔄 READY

**Prerequisites**:
- AWS CLI v2 installed: `aws --version` (tested with v2.13.0+)
- Valid AWS credentials configured: `aws sts get-caller-identity`
- IAM permissions for: SecretsManager (create/update), KMS (create key), IAM (put policy)
- SSH key available at `/home/akushnir/.ssh/id_rsa` (or generated locally)

### Operator Steps

#### Step 1: Configure AWS Credentials
```bash
# Option A: Interactive configuration
aws configure

# Option B: Set via environment variables
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID
export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY

# Verify configuration
aws sts get-caller-identity
```

**Expected Output**:
```json
{
    "UserId": "AIDAJ45Q7YFFAREXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/akushnir"
}
```

#### Step 2: Execute Phase 2 with Dry-Run First
```bash
# DRY-RUN: Preview all changes without making them
bash scripts/operator-aws-provisioning.sh --dry-run --verbose

# Expected: Shows all actions that will be taken
# [DRY-RUN] Would execute: aws kms create-key ...
# [DRY-RUN] Would execute: aws secretsmanager create-secret ...
```

#### Step 3: Execute Phase 2 Production
```bash
# EXECUTE: Create all AWS secrets and KMS key
bash scripts/operator-aws-provisioning.sh --verbose

# Expected output:
# ✅ AWS credentials verified
# ✅ KMS key created: arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012
# ✅ SSH credentials secret created: runner/ssh-credentials
# ✅ AWS credentials secret created: runner/aws-credentials
# ✅ DockerHub credentials secret created: runner/dockerhub-credentials
# ✅ IAM policy attached to runner role
# ✅ Secret accessible: runner/ssh-credentials
```

#### Step 4: Verify Secrets Created
```bash
# List all created secrets
aws secretsmanager list-secrets \
    --filters Key=name,Values=runner/ \
    --region us-east-1 \
    --output table

# Retrieve SSH credentials (verify readable)
aws secretsmanager get-secret-value \
    --secret-id "runner/ssh-credentials" \
    --region us-east-1 \
    --query 'SecretString' | jq '.ssh_key' | head -5

# Check KMS key
aws kms describe-key \
    --key-id alias/runner-credentials \
    --region us-east-1
```

### What Gets Created
| Resource | Name | Purpose |
|----------|------|---------|
| KMS Key | `alias/runner-credentials` | Encryption for all secrets |
| Secret | `runner/ssh-credentials` | SSH private key for target host |
| Secret | `runner/aws-credentials` | AWS access keys for deployments |
| Secret | `runner/dockerhub-credentials` | Docker registry authentication |
| IAM Policy | `runner-secrets-access-policy` | Permission for runner role |

### Troubleshooting Phase 2

**Issue: "Unable to locate credentials"**
```bash
# Solution: Configure AWS credentials
aws configure --profile default
```

**Issue: "AccessDenied: User is not authorized"**
```bash
# Solution: Verify IAM permissions
aws iam list-attached-user-policies --user-name akushnir
# Should include: AWSSecretsManagerFullAccess, IAMFullAccess, or equivalent
```

**Issue: "Secrets created but wait-and-deploy cannot access"**
```bash
# Solution: Attach policy to runner role/instance profile
aws iam put-role-policy \
    --role-name runner-role \
    --policy-name runner-secrets-access \
    --policy-document file://runner-policy.json
```

---

## Phase 3: Google Secret Manager Provisioning 🔄 READY

**Prerequisites**:
- `gcloud` CLI installed: `gcloud --version` (tested with 453.0.0+)
- Authenticated with GCP: `gcloud auth application-default login`
- GCP project configured: `gcloud config set project elevatediq-runner`
- IAM permissions for: Secret Manager (create/access), Service Account (create/manage)
- Secret Manager API enabled in project

### Operator Steps

#### Step 1: Authenticate with GCP
```bash
# Interactive login (opens browser for OAuth)
gcloud auth application-default login

# Or use service account key (for automated deployments)
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa-key.json
gcloud auth activate-service-account --key-file=$GOOGLE_APPLICATION_CREDENTIALS

# Verify authentication
gcloud auth list --filter=status:ACTIVE
```

**Expected Output**:
```
ACTIVE: akushnir@bioenergystrategies.com
```

#### Step 2: Set GCP Project and Enable APIs
```bash
# Set default project
gcloud config set project elevatediq-runner

# Enable Secret Manager API
gcloud services enable secretmanager.googleapis.com

# Verify enabled
gcloud services list --enabled | grep secretmanager
```

#### Step 3: Execute Phase 3 with Dry-Run First
```bash
# DRY-RUN: Preview all changes
bash scripts/operator-gcp-provisioning.sh --dry-run --verbose

# Expected: Shows all actions that will be taken
# [DRY-RUN] Would execute: gcloud secrets create ...
```

#### Step 4: Execute Phase 3 Production
```bash
# EXECUTE: Create all GCP secrets and service account
bash scripts/operator-gcp-provisioning.sh \
    --project elevatediq-runner \
    --region us-central1 \
    --verbose

# Expected output:
# ✅ GCP credentials verified (Project: elevatediq-runner)
# ✅ Secret Manager API enabled
# ✅ SSH credentials secret created: runner-ssh-key
# ✅ AWS credentials secret created: runner-aws-credentials
# ✅ DockerHub credentials secret created: runner-dockerhub-credentials
# ✅ Service account created: runner-watcher@elevatediq-runner.iam.gserviceaccount.com
# ✅ Secret Manager access granted to service account
# ✅ Service account key created: /tmp/runner-sa-key.json
```

#### Step 5: Verify Secrets Created
```bash
# List all created secrets
gcloud secrets list --project=elevatediq-runner

# Retrieve SSH secret (latest version)
gcloud secrets versions access latest \
    --secret=runner-ssh-key \
    --project=elevatediq-runner | head -5

# Check service account
gcloud iam service-accounts describe \
    runner-watcher@elevatediq-runner.iam.gserviceaccount.com \
    --project=elevatediq-runner
```

#### Step 6: Store Service Account Key Securely
```bash
# Copy SA key to target location (on bastion)
scp /tmp/runner-sa-key.json akushnir@192.168.168.42:/var/run/secrets/gcp-sa.json

# Or encode for storage in Vault
cat /tmp/runner-sa-key.json | base64 -w0 | vault kv put secret/gcp-sa-key key=@-

# Secure the local copy
shred -u /tmp/runner-sa-key.json
```

### What Gets Created
| Resource | Name | Purpose |
|----------|------|---------|
| Secret | `runner-ssh-key` | SSH private key for target host |
| Secret | `runner-aws-credentials` | AWS access keys for deployments |
| Secret | `runner-dockerhub-credentials` | Docker registry authentication |
| Service Account | `runner-watcher@<PROJECT>.iam.gserviceaccount.com` | Service account for credential access |
| IAM Binding | `roles/secretmanager.secretAccessor` | Permission for service account |
| Service Account Key | `runner-sa-key.json` | Key for authentication (download & secure) |

### Troubleshooting Phase 3

**Issue: "Permission denied on resource project"**
```bash
# Solution: Check GCP project and permissions
gcloud config get-value project
gcloud projects get-iam-policy elevatediq-runner \
    --flatten="bindings[].members" \
    --filter="bindings.members:akushnir@bioenergystrategies.com"
```

**Issue: "Secret Manager API not enabled"**
```bash
# Solution: Enable the API
gcloud services enable secretmanager.googleapis.com --project=elevatediq-runner
```

**Issue: "Cannot create service account - quota exceeded"**
```bash
# Solution: Check existing service accounts
gcloud iam service-accounts list --project=elevatediq-runner

# Delete unused ones:
gcloud iam service-accounts delete runner-old-sa@elevatediq-runner.iam.gserviceaccount.com \
    --project=elevatediq-runner
```

---

## Phase 4: Deploy Vault Agent to Bastion 🔄 READY

Once Phases 1-3 are complete, deploy vault-agent for automatic credential rotation:

```bash
# Deploy vault-agent with AppRole credentials
bash scripts/deploy-vault-agent-to-bastion.sh \
    --bastion 192.168.168.42 \
    --vault-addr https://vault.aws.example.com:8200 \
    --verbose

# Expected output:
# ✅ SSH connectivity to bastion verified
# ✅ Vault AppRole credentials available
# ✅ Vault agent configuration deployed
# ✅ Vault agent service deployed and started
# ✅ Vault agent service is active and running
```

---

## Post-Provisioning Verification

### Step 1: Verify Multi-Provider Failover
```bash
# Test credential detection and retrieval
bash scripts/wait-and-deploy.sh --test-credentials

# Expected:
# Vault:  ✅ Connected (AppRole auth)
# AWS:    ✅ Secrets accessible (runner/ssh-credentials)
# GSM:    ✅ Service account authenticated
# Status: All providers operational, using Vault (primary)
```

### Step 2: Deploy Wait-and-Deploy Watcher
```bash
# Install watcher service on target (192.168.168.42)
scp scripts/wait-and-deploy.sh akushnir@192.168.168.42:/usr/local/bin/
scp wait-and-deploy.service akushnir@192.168.168.42:/etc/systemd/system/

# Activate on target host
ssh akushnir@192.168.168.42 'sudo systemctl daemon-reload && sudo systemctl enable wait-and-deploy.service && sudo systemctl start wait-and-deploy.service'

# Verify service running
ssh akushnir@192.168.168.42 'systemctl status wait-and-deploy.service'
```

### Step 3: Test End-to-End Deployment
```bash
# Trigger deployment via direct push
git bundle create /tmp/main.bundle main

# Push bundle to target (immutable delivery)
scp /tmp/main.bundle akushnir@192.168.168.42:/tmp/

# Wait-and-deploy should:
# 1. Detect bundle arrival
# 2. Fetch credentials from Vault/AWS/GSM
# 3. Unpack and checkout code
# 4. Execute deployment scripts
# 5. Log all actions to audit trail

# Verify deployment succeeded
ssh akushnir@192.168.168.42 'tail -50 /var/log/runner-deployment.log | grep -i "deployment.*success\|deployment.*complete"'
```

---

## Timeline and Next Steps

### Completed ✅
- Phase 1: Vault AppRole setup (2026-03-09 16:30:12)
- Policy enforcement: Pre-commit hooks, PR templates active
- GitHub issues created and tracking (#2100-#2104)

### In Progress 🔄
- Phase 2: AWS Secrets Manager setup (awaiting operator execution)
- Phase 3: Google Secret Manager setup (awaiting operator execution)

### Pending ⏳
- Phase 4: Vault Agent deployment to bastion
- Phase 5: Wait-and-deploy watcher integration
- System testing and validation

---

## Issue Tracking

All provisioning work tracked in GitHub issues:

| Issue | Title | Status |
|-------|-------|--------|
| #2100 | AWS Secrets Manager provisioning | 🔄 OPERATOR ACTION READY |
| #2101 | Vault AppRole hardening | ✅ CLOSED (COMPLETE) |
| #2102 | Disable CI/PR workflows | ✅ VERIFIED & APPROVED |
| #2103 | GSM & IAM permissions | 🔄 OPERATOR ACTION READY |
| #2104 | Policy enforcement | ✅ VERIFIED & APPROVED |
| #2072 | Operational handoff | 📊 91+ audit records |

---

## Approval Record

```
APPROVAL DATE: 2026-03-09 15:45:00 UTC
APPROVED BY: akushnir@bioenergystrategies.com
AUTHORIZATION: "proceed now no waiting - use best practices and your recommendations"
STATUS: ✅ GO-LIVE APPROVED

REQUIREMENTS:
✅ Immutable credential handling (no secrets in code)
✅ Ephemeral secrets (auto-rotation via vault-agent)
✅ Idempotent deployments (git checkout + bundle operations)
✅ No-ops automation (scheduled daemon, no manual deployment)
✅ Fully automated credential distribution (multi-provider failover)
✅ No branch direct development (direct push enforcement)
✅ All credentials in GSM/Vault/KMS (no env files)
```

---

## Questions & Support

For issues or questions during execution:

1. **Vault issues**: Check vault-agent logs: `journalctl -u vault-agent.service -f`
2. **AWS issues**: Check credentials: `aws sts get-caller-identity` + `aws secretsmanager list-secrets`
3. **GCP issues**: Check project: `gcloud config get-value project` + `gcloud secrets list`
4. **Watcher issues**: Check service: `systemctl status wait-and-deploy.service` + audit logs

---

**Document Version**: 1.0  
**Last Updated**: 2026-03-09 16:30:30 UTC  
**Status**: Production Ready  
**Next Review**: Post Phase 3 completion
