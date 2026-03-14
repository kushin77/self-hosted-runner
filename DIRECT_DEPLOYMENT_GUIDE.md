# Direct Deployment - Fully Hands-Off Automation Guide

**Status**: ✅ Production Ready  
**Date**: March 14, 2026  
**Version**: 1.0  

---

## Overview

This guide describes the **direct deployment system** - a fully automated, hands-off deployment mechanism that:

- ✅ **No GitHub Actions** - Direct Cloud Build execution
- ✅ **No Pull Requests** - Direct deployment to target environments
- ✅ **Immutable Deployments** - Only version-controlled code deployed
- ✅ **Ephemeral Environments** - Temporary resources cleaned up automatically
- ✅ **Idempotent** - Safe to re-run at any time
- ✅ **Fully Automated** - Zero manual intervention required
- ✅ **GSM/Vault/KMS Credentials** - No hardcoded secrets

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Deployment Trigger                        │
│                    (deploy.sh)                               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Cloud Build (Direct Execution)                  │
│              (cloudbuild-direct-deployment.yaml)             │
├─────────────────────────────────────────────────────────────┤
│ 1. Verify Immutability       (git status check)              │
│ 2. Load Credentials          (GSM/Vault/KMS)                │
│ 3. Deploy Components         (Orchestrator)                  │
│ 4. Verify Deployment         (Health checks)                │
│ 5. Generate Audit Report     (Immutable trail)              │
│ 6. Cleanup Ephemeral         (Remove temp resources)        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│           Immutable Ephemeral Orchestrator                   │
│           (scripts/automation/orchestrator.sh)               │
├─────────────────────────────────────────────────────────────┤
│ • Credential Manager Integration                            │
│ • Component Deployment                                      │
│ • Health Verification                                       │
│ • Audit Trail Generation                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Prerequisites

```bash
# 1. Install required tools
brew install gcloud kubectl jq

# 2. Configure GCP project
gcloud config set project PROJECT_ID

# 3. Authenticate
gcloud auth application-default login

# 4. Enable Cloud Build API
gcloud services enable cloudbuild.googleapis.com
```

### Deploy to Production

```bash
# Basic deployment (prod environment, all components)
./deploy.sh --environment prod

# Deploy specific components
./deploy.sh --environment prod --components k8s-health-checks

# Deploy to staging
./deploy.sh --environment staging --components all

# Dry-run test
./deploy.sh --environment prod --dry-run
```

### Monitor Deployment

```bash
# View build logs in real-time
gcloud builds log BUILD_ID --stream

# Check deployment status
kubectl get deployment -n prod

# View audit trail
cat scripts/automation/audit/orchestration_*.log
```

---

## Components

### 1. Credential Manager (`scripts/automation/credential-manager.sh`)

Unified credential management with automatic failover:

```bash
# Load credentials from GSM/Vault/KMS
source scripts/automation/credential-manager.sh

# Get single credential
SECRET_VALUE=$(get_secret "database-password" "prod")

# Load multiple credentials to environment
load_credentials_to_env "db-password,api-key,tls-cert" "prod"

# List all secrets
list_all_secrets "prod"

# Rotate credential
rotate_credential "api-key" "new-api-key-value" "prod"

# Verify access
verify_credential_access "prod"
```

**Credential Hierarchy**:
1. **Primary**: Google Secret Manager (GSM)
2. **Secondary**: HashiCorp Vault
3. **Tertiary**: Google Cloud KMS (encrypted)

### 2. Immutable Ephemeral Orchestrator (`scripts/automation/orchestrator.sh`)

Direct deployment automation:

```bash
# Deploy all components
./scripts/automation/orchestrator.sh --operation deploy --environment prod

# Deploy specific component
./scripts/automation/orchestrator.sh --operation deploy --environment prod --component k8s-health-checks

# Verify deployment
./scripts/automation/orchestrator.sh --operation verify --environment prod

# Clean up ephemeral resources
./scripts/automation/orchestrator.sh --operation cleanup --environment prod
```

**Design Principles**:
- **Immutable**: No state changes outside git
- **Ephemeral**: Temporary resources destroyed after use
- **Idempotent**: Safe re-execution produces same results
- **No-ops**: Fully automated, hands-off

### 3. Cloud Build Configuration (`cloudbuild-direct-deployment.yaml`)

Six-step deployment pipeline:

1. **Verify Immutability** - Ensure clean git state
2. **Load Credentials** - Fetch from GSM/Vault/KMS
3. **Deploy Components** - Run orchestrator
4. **Verify Deployment** - Health checks
5. **Commit Changes** - Immutable audit trail
6. **Cleanup** - Remove ephemeral resources

### 4. Deployment Trigger (`deploy.sh`)

Simple deployment entry point:

```bash
./deploy.sh [OPTIONS]

Options:
  --environment ENVIRONMENT   Target environment (prod/staging/dev/qa)
  --components COMPONENTS     Components to deploy (all/k8s-health-checks/etc)
  --skip-verification        Skip deployment verification
  --dry-run                  Test without deployment
  --no-watch                 Don't watch build progress
```

---

## Credential Management

### Google Secret Manager (Primary)

```bash
# Create secret in GSM for production
echo "your-secret-value" | gcloud secrets create prod/database-password \
  --data-file=- \
  --project=PROJECT_ID

# Label secret for environment
gcloud secrets add-iam-policy-binding prod/database-password \
  --member=serviceAccount:cloud-build@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor
```

### HashiCorp Vault (Secondary)

```bash
# Store secret in Vault
vault kv put secret/prod/database-password value="your-secret-value"

# Set Vault token
export VAULT_TOKEN="your-token"
echo "$VAULT_TOKEN" > ~/.vault-token

# Verify Vault access
curl -H "X-Vault-Token: $VAULT_TOKEN" \
  $VAULT_ADDR/v1/sys/health
```

### Google Cloud KMS (Tertiary)

```bash
# Create KMS key ring and key
gcloud kms keyrings create deployment-keys \
  --location=global

gcloud kms keys create main \
  --location=global \
  --keyring=deployment-keys \
  --purpose=encryption

# Encrypt credential
echo "secret-value" | gcloud kms encrypt \
  --location=global \
  --keyring=deployment-keys \
  --key=main \
  --plaintext-file=- \
  --ciphertext-file=-
```

---

## Deployment Workflow

### Step-by-Step Execution

```bash
# 1. Verify prerequisites
./deploy.sh --environment prod --dry-run

# 2. Check git status
git status

# 3. Ensure all changes committed
git add . && git commit -m "Ready for deployment"

# 4. Trigger deployment
./deploy.sh --environment prod --components all

# 5. Monitor build
gcloud builds log BUILD_ID --stream

# 6. Verify deployment
kubectl get deployment -n prod

# 7. Check health
./scripts/k8s-health-checks/cluster-readiness.sh

# 8. Review audit trail
cat scripts/automation/audit/orchestration_*.log
```

### Example: Multi-Component Deployment

```bash
# Deploy entire stack to production
./deploy.sh --environment prod --components all

# What gets deployed:
# 1. Kubernetes Health Checks (k8s-health-checks)
# 2. Multi-Cloud Secrets Validation (multi-cloud-secrets)
# 3. Security Audit (security-audit)
# 4. Multi-Region Failover (multi-region-failover)
```

---

## Immutability Guarantees

### Git-Based Immutability

- ✅ Only version-controlled code deployed
- ✅ All deployments tagged with git commit SHA
- ✅ Complete audit trail in git history
- ✅ Reproducible deployments from any commit

### Credential Immutability

- ✅ Credentials never stored in repositories
- ✅ All credentials in GSM/Vault/KMS
- ✅ Automatic secret rotation support
- ✅ Audit trail for all credential access

### Deployment Immutability

- ✅ Idempotent operations (safe re-runs)
- ✅ Ephemeral resources cleaned up
- ✅ No persistent state outside git
- ✅ Reproducible from any point in time

---

## Idempotency

All operations are fully idempotent - safe to re-run:

```bash
# Running deployment multiple times is safe
./deploy.sh --environment prod
./deploy.sh --environment prod  # Same result
./deploy.sh --environment prod  # Same result ✓

# Components handle state correctly:
# ✓ Already-deployed components updated in-place
# ✓ No duplicate resources created
# ✓ No rolled-back deployments
# ✓ Safe concurrent execution
```

---

## Monitoring & Verification

### Build Status

```bash
# Check build status
gcloud builds describe BUILD_ID --format='value(status)'

# View build logs
gcloud builds log BUILD_ID --stream

# List recent builds
gcloud builds list --limit=10
```

### Deployment Health

```bash
# Check Kubernetes deployments
kubectl get deployment -n prod

# View pod status
kubectl get pods -n prod

# Check service status
kubectl get svc -n prod

# View events
kubectl get events -n prod
```

### Audit Trail

```bash
# View orchestration logs
cat scripts/automation/audit/orchestration_*.log

# View deployment report
cat scripts/automation/reports/deployment_*.md

# Check git history
git log --oneline --all | head -20
```

---

## Troubleshooting

### Build Failures

```bash
# 1. Check build logs
gcloud builds log BUILD_ID --stream

# 2. Verify prerequisites
./deploy.sh --dry-run --environment prod

# 3. Check git state
git status

# 4. Verify GCP access
gcloud auth application-default print-access-token
```

### Credential Issues

```bash
# 1. Verify GSM access
gcloud secrets list --project=PROJECT_ID

# 2. Check Vault connectivity
curl $VAULT_ADDR/v1/sys/health

# 3. Verify KMS permissions
gcloud kms decrypt --help

# 4. Check service account permissions
gcloud iam service-accounts get-iam-policy cloud-build@PROJECT_ID.iam.gserviceaccount.com
```

### Deployment Verification Failures

```bash
# 1. Check orchestrator logs
tail -50 scripts/automation/audit/orchestration_*.log

# 2. Verify Health checks
./scripts/k8s-health-checks/cluster-readiness.sh

# 3. Check component status
kubectl get all -n prod

# 4. Review deployment events
kubectl describe deployment -n prod NAME
```

---

## Security Best Practices

### 1. Service Account Management

```bash
# Create dedicated service account for deployments
gcloud iam service-accounts create deployment-bot

# Grant minimal required permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member=serviceAccount:deployment-bot@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/container.developer

# Use service account for deployments
gcloud auth activate-service-account \
  deployment-bot@PROJECT_ID.iam.gserviceaccount.com
```

### 2. Credential Rotation

```bash
# Rotate credentials regularly
./scripts/automation/credential-manager.sh
rotate_credential "api-key" "new-value" "prod"

# Audit credential access
gcloud logging read "resource.type=secretmanager.googleapis.com"
```

### 3. Audit Trail Management

```bash
# Enable Cloud Audit Logs
gcloud logging sinks create cloudbuild-audit \
  --log-filter='resource.type=cloud_build'

# View audit logs
gcloud logging read "resource.type=cloud_build"
```

---

## CI/CD Integration

### Scheduled Deployments

```bash
# Create Cloud Scheduler job
gcloud scheduler jobs create app-engine redeploy-prod \
  --schedule="0 2 * * *" \
  --http-method=POST \
  --uri=https://cloudbuild.googleapis.com/v1/projects/PROJECT_ID/builds \
  --message-body='{"source":{"branchName":"main"},"substitutions":{"_ENVIRONMENT":"prod"}}'
```

### Event-Driven Deployments

```yaml
# Cloud Build trigger on git push
gcloud builds triggers create github \
  --name "deploy-prod" \
  --repo-owner GITHUB_USER \
  --repo-name REPO_NAME \
  --branch-pattern "^main$" \
  --build-config "cloudbuild-direct-deployment.yaml" \
  --substitutions "_ENVIRONMENT=prod"
```

---

## FAQ

**Q: Why no GitHub Actions?**  
A: Direct Cloud Build execution provides faster feedback, better credential isolation, and simpler troubleshooting without GitHub workflow complexity.

**Q: Why immutable deployments?**  
A: Ensures reproducibility, audit trail, and ability to rollback to any previous state via git history.

**Q: What if deployment fails?**  
A: Ephemeral resources are automatically cleaned up. Fix the issue and re-run - safe to repeat.

**Q: How do credentials stay secure?**  
A: All credentials in GSM/Vault/KMS - never stored in code or logs. Automatic rotation supported.

**Q: Can I deploy to multiple environments?**  
A: Yes - use different values for `--environment` flag (prod/staging/dev/qa).

---

## Support

**Documentation**: See individual component READMEs in `scripts/` directory  
**Issues**: Report via GitHub issues tracker  
**Logs**: Check `scripts/automation/audit/` and `scripts/automation/reports/`  

---

**Generated**: March 14, 2026  
**Status**: ✅ Production Ready  
**Maintained by**: Immutable Ephemeral Orchestrator
