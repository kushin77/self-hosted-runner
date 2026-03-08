GCP_GSM_INTEGRATION_GUIDE.md# 🔐 GCP Secret Manager Integration Guide

**Tier**: Infrastructure (Tier 1 - Critical)  
**Deployment Date**: March 8, 2026  
**Status**: ✅ Production Ready  
**System Properties**: Immutable | Ephemeral | Idempotent | No-Ops | Hands-Off

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Setup & Configuration](#setup--configuration)
5. [Operational Procedures](#operational-procedures)
6. [Emergency Procedures](#emergency-procedures)
7. [Monitoring & Compliance](#monitoring--compliance)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### Purpose
GCP Secret Manager (GSM) integration provides:
- **Multi-cloud credentials management** (AWS ↔ GCP ↔ Vault)
- **Automated secret synchronization** (GitHub ↔ GSM every 15 min)
- **Credential lifecycle management** (rotation, audit, compliance)
- **Emergency breach response** (automated revocation, incident tracking)

### Key Benefits
- ✅ Centralized credential storage beyond GitHub
- ✅ Immutable audit trail (every access logged)
- ✅ Automated rotation tracking (30-90 day policies)
- ✅ Emergency breach recovery (<2 min automated response)
- ✅ Zero manual secret management (fully automated)

### System Properties
| Property | Status | Details |
|----------|--------|---------|
| **Immutable** | ✅ | All logic in Git, no state persistence |
| **Ephemeral** | ✅ | State resets each workflow cycle |
| **Idempotent** | ✅ | Safe to re-run any workflow |
| **No-Ops** | ✅ | Fully scheduled (no manual triggers) |
| **Hands-Off** | ✅ | Operator adds secrets, system handles rest |

---

## Architecture

### 4-Layer System Design

#### Layer 1: Secret Synchronization (Every 15 Min)
```
GitHub Secrets ↔ GCP Secret Manager
    ↓
Workflow: gcp-gsm-sync-secrets.yml
Script: scripts/automation/gcp-gsm-sync.sh
    ↓
Actions:
  - Read GitHub secrets (via environment)
  - Upsert to GSM (idempotent)
  - Verify consistency
  - Generate audit log
```

**Secrets Synced**:
- GCP credentials (service account, project ID, workload provider)
- AWS credentials (OIDC role, assume role)
- Integration tokens (Slack, Vault)
- Authentication URLs (Vault address)

#### Layer 2: Credential Rotation (Daily at 2 AM UTC)
```
Workflow: gcp-gsm-rotation.yml
Script: scripts/automation/gcp-gsm-rotation.sh
    ↓
Daily Checks:
  - Get age of each GSM secret version
  - Compare against TTL policy
  - Mark for rotation if overdue
  - Archive old versions (keep 3)
  - Notify operator via GitHub issue
```

**Rotation Policies**:
| Secret | Max Age | Action |
|--------|---------|--------|
| GCP Service Account | 30 days | Archive versions, mark for rotation |
| AWS OIDC Role | 90 days | Create tracking issue |
| Slack Bot Token | 60 days | Generate incident issue |
| Vault Token | 45 days | Archive + notify |

#### Layer 3: Breach Response (On-Demand)
```
Workflow: gcp-gsm-breach-recovery.yml
Script: scripts/automation/gcp-gsm-emergency-recovery.sh
    ↓
Triggers:
  - Workflow dispatch (manual)
  - Issue comment (/breach, /revoke-secret, /emergency-rotate)
    ↓
Actions (< 2 minutes):
  - Immediately revoke compromised secret
  - Destroy all versions
  - Mark as revoked in metadata
  - Create audit entry
  - Send escalation notification
  - Generate incident report
```

#### Layer 4: Monitoring & Audit (Every 5 Min)
```
Workflow: gcp-gsm-rotation.yml (audit step)
Actions:
  - Verify all secrets accessible
  - Check version consistency
  - Archive audit logs
  - Flag overdue rotations
```

### Data Flow Diagram
```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                        │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ GitHub Secrets Tab                                       │  │
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
│ │ - GCP_PROJECT_ID                                         │  │
│ │ - AWS_OIDC_ROLE_ARN                                      │  │
│ │ - SLACK_BOT_TOKEN                                        │  │
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
│ └────────┬──────────────────────────────────────────────────┘  │
│          │ Every 15 min (sync workflow)                        │
│          ↓                                                      │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ .github/workflows/gcp-gsm-sync-secrets.yml               │  │
│ │ Runs:scripts/automation/gcp-gsm-sync.sh                  │  │
│ └────────┬──────────────────────────────────────────────────┘  │
└─────────┼──────────────────────────────────────────────────────┘
          │
          │ GCP OIDC Authentication
          │   (workload_identity_provider + service_account_email)
          ↓
┌─────────────────────────────────────────────────────────────────┐
│                    GCP Secret Manager                           │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ Secrets (auto-replicated, immutable versions)            │  │
│ │ - gcp-service-account (v5, v4, v3...)                    │  │
│ │ - aws-oidc-role-arn   (v2, v1...)                        │  │
│ │ - slack-bot-token     (v8, v7...)                        │  │
│ │ - vault-token         (v1...)                            │  │
│ └──────────────────────────────────────────────────────────┘  │
│          ↑ Every 15 min (sync)                               │  │
│          │ Daily 2 AM UTC (rotation check)                   │  │
│          │ On-demand (breach response)                       │  │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ Metadata & Audit                                         │  │
│ │ - labels: gh-saas-sync, rotation-pending                 │  │
│ │ - immutable audit trail (every access logged)            │  │
│ │ - version history (auto-archived after 3 versions)       │  │
│ └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
          ↓
   ┌──────────────┐
   │ Active Use   │
   │ by Workflows │
   │ (terraform,  │
   │  tests, etc) │
   └──────────────┘
```

---

## Prerequisites

### GCP Setup
1. **Google Cloud Project** (active)
2. **Service Account** with permissions:
   ```
   - secretmanager.secrets.create
   - secretmanager.secrets.update
   - secretmanager.secretVersions.add
   - secretmanager.secretVersions.destroy
   - secretmanager.secretVersions.access
   ```
3. **Workload Identity Federation** configured (OIDC)
   - Provider: GitHub
   - Audience: GitHub Actions

### GitHub Setup
1. **Repository Secrets** (minimal - only GCP bootstrap):
   ```
   GCP_PROJECT_ID                    # Your GCP project ID
   GCP_SERVICE_ACCOUNT_EMAIL         # service-account@project.iam.gserviceaccount.com
   GCP_WORKLOAD_IDENTITY_PROVIDER    # projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider
   GCP_SERVICE_ACCOUNT_KEY           # JSON credentials (fallback, optional with OIDC)
   ```

2. **Issue Labels** (for automation):
   - `emergency` (breach response)
   - `gcp-gsm` (categorization)
   - `ops` (operations)

---

## Setup & Configuration

### Step 1: GCP Project Configuration

#### 1.1 Create Service Account
```bash
gcloud iam service-accounts create github-gsm-manager \
  --display-name="GitHub GSM Manager" \
  --project=YOUR_PROJECT_ID
```

#### 1.2 Grant Permissions
```bash
PROJECT_ID="YOUR_PROJECT_ID"
SERVICE_ACCOUNT="github-gsm-manager@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant secret management permissions
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.admin"
```

#### 1.3 Setup Workload Identity Federation
```bash
# Create workload identity pool
gcloud iam workload-identity-pools create "github-pool" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions"

# Create provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub" \
  --attribute-mapping="google.subject=assertion.sub,assertion.aud=assertion.aud,assertion.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Grant service account impersonation permission
gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_ID/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR_GITHUB_ORG/YOUR_REPO"
```

### Step 2: GitHub Configuration

#### 2.1 Add Repository Secrets
```bash
gh secret set GCP_PROJECT_ID --body "your-project-id"
gh secret set GCP_SERVICE_ACCOUNT_EMAIL --body "github-gsm-manager@project.iam.gserviceaccount.com"
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider"

# Optional: Service account key JSON (for fallback)
gh secret set GCP_SERVICE_ACCOUNT_KEY --body "$(cat /path/to/service-account-key.json)"
```

#### 2.2 Add Integration Secrets
```bash
# AWS
gh secret set AWS_OIDC_ROLE_ARN --body "arn:aws:iam::ACCOUNT:role/github-oidc-role"
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::ACCOUNT:role/gh-automation-role"

# Slack (if using notifications)
gh secret set SLACK_BOT_TOKEN --body "xoxb-your-token"

# Vault (if using Vault integration)
gh secret set VAULT_ADDR --body "https://vault.example.com"
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
```

### Step 3: Verify Setup

#### 3.1 Test GCP Authentication
```bash
# In GitHub Actions workflow context:
gcloud auth list
gcloud secrets list --project=$GCP_PROJECT_ID
```

#### 3.2 Test Sync Workflow
```bash
# Manually trigger sync workflow
gh workflow run gcp-gsm-sync-secrets.yml

# Monitor execution
gh run list --workflow=gcp-gsm-sync-secrets.yml --limit 1
```

---

## Operational Procedures

### Routine Operations

#### Adding a New Secret to GSM Sync
1. **Add to GitHub Secrets**:
   ```bash
   gh secret set NEW_SECRET_NAME --body "secret-value"
   ```

2. **Update sync script** (`scripts/automation/gcp-gsm-sync.sh`):
   ```bash
   # Add to secrets_to_sync array:
   declare -a secrets_to_sync=(
     ...
     "NEW_SECRET_NAME:gsm-secret-name"
   )
   ```

3. **Wait for next sync** (or manually trigger):
   ```bash
   gh workflow run gcp-gsm-sync-secrets.yml
   ```

4. **Verify in GSM**:
   ```bash
   gcloud secrets versions access latest --secret="gsm-secret-name"
   ```

#### Rotating a Credential
1. **Generate new credential** in source system (AWS, GCP, Vault)
2. **Update GitHub Secret**:
   ```bash
   gh secret set SECRET_NAME --body "new-secret-value"
   ```
3. **System automatically**:
   - Detects via next sync (15 min max)
   - Creates new GSM version
   - Archives old versions
   - Updates audit log

#### Monitoring Secret Status
```bash
# List all synced secrets in GSM
gcloud secrets list --filter="labels.gh-saas-sync:true"

# Get metadata of a specific secret
gcloud secrets describe gcp-service-account

# View version history
gcloud secrets versions list gcp-service-account

# Access latest version
gcloud secrets versions access latest --secret="gcp-service-account"
```

---

## Emergency Procedures

### Procedure 1: Suspected Credential Compromise

**Timeline**: < 2 minutes automated response

#### Step 1: Detect Breach
```bash
# Option A: Manual detection
# On issue or Slack notification of compromise

# Option B: Automated detection
# (System monitoring integration would trigger)
```

#### Step 2: Initiate Emergency Response
**Via GitHub Issue Comment**:
```
@github-actions /breach gcp-service-account detected
```

**Via Workflow Dispatch**:
```bash
gh workflow run gcp-gsm-breach-recovery.yml \
  -f action=compromise \
  -f secret_name=gcp-service-account \
  -f reason="github_logs_exposed"
```

#### Step 3: Automated Actions (Automatic)
- ✅ All versions of secret immediately destroyed
- ✅ Metadata marked "revoked"
- ✅ Audit entry created
- ✅ Incident report generated
- ✅ Slack notification sent
- ✅ High-priority issue created

#### Step 4: Operator Actions (Required)
1. **Investigate** root cause (how was it exposed?)
2. **Generate** new credential in source system
3. **Update** GitHub secret with new value
4. **Verify** system syncs to GSM (15 min)
5. **Monitor** for unauthorized usage attempts

### Procedure 2: Accidental Exposure in Logs/CI

#### Step 1: Initiate Response
```bash
gh workflow run gcp-gsm-breach-recovery.yml \
  -f action=exposure \
  -f secret_name=slack-bot-token \
  -f reason="ci_logs_directory"
```

#### Step 2: System Response (Automatic)
- ✅ Secret revoked
- ✅ Versions destroyed
- ✅ Incident tracked

#### Step 3: Operator Cleanup
1. Scrub exposure location from logs
2. Update credentials
3. Monitor for misuse

### Procedure 3: Mass Emergency Rotation

**Use Case**: Suspected widespread compromise, regulatory incident

```bash
gh workflow run gcp-gsm-breach-recovery.yml \
  -f action=mass-rotate
```

**Result**:
- ✅ ALL monitored secrets revoked simultaneously  
- ✅ All versions destroyed
- ✅ High-severity incident created
- ✅ Escalation notification sent

**Operator Must**:
1. Rotate ALL credentials in source systems immediately
2. Update ALL GitHub secrets
3. Execute full system validation

---

## Monitoring & Compliance

### Daily Rotation Check (2 AM UTC)
```bash
# Automated workflow detects overdue credentials
# Creates issues for operator if TTL exceeded

# Status visible in:
# - Issue #1381 (auto-updated)
# - Workflow logs
# - Rotation audit reports
```

### Audit Trail Access
```bash
# View all GSM operations
gcloud logging read "resource.type=secretmanager.googleapis.com" \
  --limit=100 \
  --format=json

# Export audit for compliance
gcloud logging read "security" --format=json > audit-export.json
```

### Compliance Reports
```bash
# Automated reports generated in:
# .github/workflows/logs/
#   - gcp-gsm-sync-TIMESTAMP.log
#   - gcp-gsm-rotation-audit-TIMESTAMP.md
#   - incident-report-TIMESTAMP.md
```

---

## Troubleshooting

### Issue 1: Authentication Fails

**Error**: `google.auth.exceptions.DefaultCredentialsError`

**Solutions**:
```bash
# Verify OIDC provider configuration
gcloud iam workload-identity-pools providers describe github-provider \
  --location=global \
  --workload-identity-pool=github-pool

# Verify service account has impersonation permission
gcloud iam service-accounts get-iam-policy \
  "github-gsm-manager@PROJECT_ID.iam.gserviceaccount.com"

# Test with explicit key (fallback)
gcloud auth activate-service-account --key-file=key.json
```

### Issue 2: Secret Sync Fails

**Error**: `gcloud secrets versions add' returns error`

**Solutions**:
```bash
# Check secret permissions
gcloud secrets get-iam-policy gcp-service-account

# Verify service account has secret.admin role
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --format='table(bindings.role)' \
  --filter="bindings.members:serviceAccount:github-gsm-manager@*"

# Manually create secret if missing
gcloud secrets create gcp-service-account \
  --replication-policy=automatic
```

### Issue 3: Rotation Check Fails

**Error**: `Can't access secret versions`

**Solutions**:
```bash
# List secrets and check for access issues
gcloud secrets list --project=PROJECT_ID

# Verify serviceaccount has secretVersions.access role  
gcloud secrets get-iam-policy SECRET_NAME
```

### Debug Commands
```bash
# Full sync log
tail -100 .github/workflows/logs/gcp-gsm-sync-*.log

# Rotation audit report
cat .github/workflows/logs/gcp-gsm-rotation-audit-*.md

# Recent incident reports
ls -lt .github/workflows/logs/incident-report-*.md | head -5

# Live monitoring
watch -n 5 'gcloud secrets list --project=PROJECT_ID'
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| **Manual sync** | `gh workflow run gcp-gsm-sync-secrets.yml` |
| **Check rotations** | `gh workflow run gcp-gsm-rotation.yml` |
| **Emergency response** | `gh workflow run gcp-gsm-breach-recovery.yml` |
| **View secrets** | `gcloud secrets list` |
| **Revoke secret** | `./scripts/automation/gcp-gsm-emergency-recovery.sh revoke SECRET_NAME` |
| **Check secret age** | `gcloud secrets versions list SECRET_NAME` |
| **View sync logs** | `tail .github/workflows/logs/gcp-gsm-sync-*.log` |

---

## Support & Escalation

| Issue | Escalation | Timeline |
|-------|-----------|----------|
| **Sync failure** | Check workflow logs → Issue #1381 | 15 min |
| **Rotation overdue** | Auto-created issue → Review + rotate | Daily |
| **Data breach** | Immediate revocation → Issue creation → Slack alert | < 2 min |
| **System malfunction** | Check guides → Contact infrastructure team | ASAP |

---

**Last Updated**: March 8, 2026  
**Maintained By**: GitHub Actions Automation  
**Contact**: ops@example.com  
**Runbook**: This document + `.github/workflows/` files
