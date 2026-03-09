# Self-Healing Orchestration Framework — Deployment Guide

**Complete step-by-step guide for deploying and configuring the self-healing orchestration system.**

**Last Updated:** March 8, 2026  
**Target Audience:** DevOps Engineers, SREs, Platform Engineers

---

## Table of Contents

1. [Quick Start (5 minutes)](#quick-start)
2. [Credential Provider Setup](#credential-provider-setup)
3. [GitHub Actions Configuration](#github-actions-configuration)
4. [OIDC/WIF Setup](#oidcwif-setup)
5. [Monitoring & Alerting](#monitoring--alerting)
6. [Troubleshooting](#troubleshooting)
7. [Best Practices](#best-practices)

---

## Quick Start

### Prerequisites
- Python 3.10+
- Git with push access
- One credential provider installed:
  - **Vault** (recommended for on-prem)
  - **Google Secret Manager** (recommended for GCP)
  - **AWS Secrets Manager** (recommended for AWS)

### Installation

**1. Clone and install:**
```bash
git clone https://github.com/kushin77/self-hosted-runner.git
cd self-hosted-runner
pip install -r requirements.txt
```

**2. Run tests locally:**
```bash
pytest self_healing_orchestrator/ -v

# Expected output:
# ======================== 26 passed in 2.34s ==========================
```

**3. Merge all Draft issues to main** (in sequence):
```bash
# Pull all feature branches
git fetch origin

# Merge Draft issues in order
gh pr merge 1912 --squash   # Orchestration framework
gh pr merge 1924 --squash   # Integration adapters  
gh pr merge 1929 --squash   # Credential providers
gh pr merge 1928 --squash   # GitHub adapters
gh pr merge 1930 --squash   # CI/CD pipeline
gh pr merge 1938 --squash   # Observability
```

**4. Add GitHub secrets** (repository settings):
```
VAULT_ADDR = https://vault.example.com
VAULT_TOKEN = s.xxxxx
GCP_PROJECT_ID = my-project
AWS_REGION = us-east-1
AWS_ROLE_ARN = arn:aws:iam::123456789012:role/orchestrator
```

**5. Done.** Workflows automatically run on next push to main.

---

## Credential Provider Setup

### HashiCorp Vault (Recommended for On-Prem)

**Step 1: Create secrets in Vault**
```bash
# Set Vault address
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="s.xxxxx"

# Create secrets
vault kv put secret/github-token \
  value="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"

vault kv put secret/slack-webhook \
  value="https://hooks.slack.com/services/XXXXX"

vault kv put secret/pagerduty-key \
  value="xxxxxxxxxxxxxxxxxxxxx"
```

**Step 2: Create AppRole policy**
```bash
cat > /tmp/orchestrator-policy.hcl <<EOF
path "secret/data/github-token" {
  capabilities = ["read"]
}
path "secret/data/slack-webhook" {
  capabilities = ["read"]
}
path "secret/data/pagerduty-key" {
  capabilities = ["read"]
}
EOF

vault policy write orchestrator /tmp/orchestrator-policy.hcl
```

**Step 3: Issue token**
```bash
# For manual testing
vault token create \
  -policy=orchestrator \
  -ttl=24h \
  -display-name="orchestrator-manual"

# For CI/CD (recommended: use OIDC instead, see section 4)
vault write -f auth/approle/role/orchestrator
vault read auth/approle/role/orchestrator/role-id
vault write -f auth/approle/role/orchestrator/secret-id
```

**Step 4: Configure GitHub Actions**
```yaml
# In your repo, go to Settings → Secrets and variables → Actions
# Add these secrets:
VAULT_ADDR = https://vault.example.com
VAULT_TOKEN = s.xxxxx  # Use OIDC instead (recommended)
```

---

### Google Secret Manager (Recommended for GCP)

**Step 1: Create secrets**
```bash
export GCP_PROJECT_ID="my-project"

gcloud secrets create orchestrator-github-token
echo -n "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx" | \
  gcloud secrets versions add orchestrator-github-token --data-file=-

gcloud secrets create orchestrator-slack-webhook
echo -n "https://hooks.slack.com/services/XXXXX" | \
  gcloud secrets versions add orchestrator-slack-webhook --data-file=-

gcloud secrets create orchestrator-pagerduty-key
echo -n "xxxxxxxxxxxxxxxxxxxxx" | \
  gcloud secrets versions add orchestrator-pagerduty-key --data-file=-
```

**Step 2: Create service account**
```bash
# Create service account
gcloud iam service-accounts create orchestrator-sa \
  --display-name="Self-Healing Orchestrator"

# Grant Secret Accessor role
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:orchestrator-sa@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

**Step 3: Create Workload Identity Pool (OIDC)**
```bash
# Create workload identity pool
gcloud iam workload-identity-pools create "github" \
  --project=$GCP_PROJECT_ID \
  --location="global" \
  --display-name="GitHub Actions"

# Get pool resource name
WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools describe github \
  --project=$GCP_PROJECT_ID \
  --location=global \
  --format='value(name)')

# Create OIDC provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project=$GCP_PROJECT_ID \
  --location="global" \
  --workload-identity-pool="github" \
  --display-name="GitHub" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.aud=assertion.aud,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Grant GitHub Actions access
gcloud iam service-accounts add-iam-policy-binding \
  orchestrator-sa@$GCP_PROJECT_ID.iam.gserviceaccount.com \
  --project=$GCP_PROJECT_ID \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/kushin77/self-hosted-runner"
```

**Step 4: Configure GitHub Actions**
```yaml
# In your repo, go to Settings → Secrets and variables → Actions
GCP_PROJECT_ID = my-project
GCP_WORKLOAD_IDENTITY_PROVIDER = <from above>
GCP_SERVICE_ACCOUNT = orchestrator-sa@my-project.iam.gserviceaccount.com
```

---

### AWS Secrets Manager (Recommended for AWS)

**Step 1: Create secrets**
```bash
export AWS_REGION="us-east-1"

# Create secrets
aws secretsmanager create-secret \
  --name orchestrator/github-token \
  --secret-string "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
  --region $AWS_REGION

aws secretsmanager create-secret \
  --name orchestrator/slack-webhook \
  --secret-string "https://hooks.slack.com/services/XXXXX" \
  --region $AWS_REGION

aws secretsmanager create-secret \
  --name orchestrator/pagerduty-key \
  --secret-string "xxxxxxxxxxxxxxxxxxxxx" \
  --region $AWS_REGION
```

**Step 2: Create IAM role**
```bash
# Create role
aws iam create-role \
  --role-name orchestrator-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
          },
          "StringLike": {
            "token.actions.githubusercontent.com:sub": "repo:kushin77/self-hosted-runner:*"
          }
        }
      }
    ]
  }'

# Grant SecretManager permissions
aws iam put-role-policy \
  --role-name orchestrator-role \
  --policy-name secrets-access \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ],
        "Resource": "arn:aws:secretsmanager:*:123456789012:secret:orchestrator/*"
      }
    ]
  }'
```

**Step 3: Create OIDC Provider**
```bash
# Check if provider exists
aws iam list-open-id-connect-providers

# If not, create it
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
```

**Step 4: Configure GitHub Actions**
```yaml
# In your repo, go to Settings → Secrets and variables → Actions
AWS_REGION = us-east-1
AWS_ROLE_ARN = arn:aws:iam::123456789012:role/orchestrator-role
```

---

## GitHub Actions Configuration

### Deploy Workflow

Once Draft issues are merged, the deployment workflow runs automatically:

```yaml
# .github/workflows/deploy.yml
name: Deploy Orchestration

on:
  push:
    branches: [main]
    paths:
      - 'self_healing_orchestrator/**'
      - 'requirements.txt'
      - '.github/workflows/deploy.yml'

permissions:
  contents: read
  id-token: write  # For OIDC

jobs:
  orchestrate:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: actions/setup-python@v4
        with:
          python-version: '3.12'
      
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
      
      - name: Assume AWS role (if using AWS)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}
      
      - name: Authenticate to Google Cloud (if using GCP)
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}
      
      - name: Run orchestration
        run: |
          python3 -m self_healing_orchestrator.integration
        env:
          VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
          VAULT_TOKEN: ${{ secrets.VAULT_TOKEN }}
          GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
          AWS_REGION: ${{ secrets.AWS_REGION }}
      
      - name: Upload deployment report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: deployment-report
          path: deployment-report-*.json
```

---

## OIDC/WIF Setup

### Why Use OIDC/WIF Instead of Long-Lived Tokens?

- ✅ **No token storage:** OIDC generates short-lived credentials on-the-fly
- ✅ **Automatic expiration:** Credentials valid for ~5 minutes
- ✅ **Audit trail:** Each token includes repository, branch, commit context
- ✅ **Revocation:** No need to rotate long-lived secrets
- ❌ **Not suitable for:** Vault (which expects tokens) — for Vault, use AppRole + IP whitelisting

### AWS Setup (Complete Example)

```bash
#!/bin/bash
# deploy-aws-oidc.sh

AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-east-1"
GITHUB_REPO="kushin77/self-hosted-runner"

# 1. Create OIDC provider
echo "Creating OIDC provider..."
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  --region $AWS_REGION 2>/dev/null || echo "Provider already exists"

# 2. Create IAM role with assume-role policy for GitHub
echo "Creating IAM role..."
aws iam create-role \
  --role-name "github-orchestrator-role" \
  --assume-role-policy-document file:///tmp/assume-role-policy.json \
  --region $AWS_REGION

# 3. Attach policy for secrets access
aws iam put-role-policy \
  --role-name "github-orchestrator-role" \
  --policy-name "secrets-access" \
  --policy-document file:///tmp/secrets-policy.json

# 4. Add to GitHub secrets
echo "GitHub secrets to add:"
echo "AWS_ROLE_ARN=arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-orchestrator-role"
echo "AWS_REGION=${AWS_REGION}"
```

### GCP Setup (Complete Example)

```bash
#!/bin/bash
# deploy-gcp-oidc.sh

GCP_PROJECT_ID="my-project"
GCP_REGION="global"
GITHUB_REPO="kushin77/self-hosted-runner"

# 1. Create workload identity pool
echo "Creating workload identity pool..."
gcloud iam workload-identity-pools create "github" \
  --project=$GCP_PROJECT_ID \
  --location=$GCP_REGION \
  --display-name="GitHub Actions"

WORKLOAD_POOL_ID=$(gcloud iam workload-identity-pools describe github \
  --project=$GCP_PROJECT_ID \
  --location=$GCP_REGION \
  --format='value(name)')

# 2. Create OIDC provider
echo "Creating OIDC provider..."
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project=$GCP_PROJECT_ID \
  --location=$GCP_REGION \
  --workload-identity-pool="github" \
  --display-name="GitHub" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# 3. Grant service account access
echo "Granting service account access..."
gcloud iam service-accounts add-iam-policy-binding \
  orchestrator-sa@$GCP_PROJECT_ID.iam.gserviceaccount.com \
  --project=$GCP_PROJECT_ID \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_POOL_ID}/attribute.repository/${GITHUB_REPO}"

# 4. Add to GitHub secrets
echo "GitHub secrets to add:"
echo "GCP_WORKLOAD_IDENTITY_PROVIDER=${WORKLOAD_POOL_ID}/providers/github-provider"
echo "GCP_SERVICE_ACCOUNT=orchestrator-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
```

---

## Monitoring & Alerting

### Prometheus Setup

**1. Install Prometheus:**
```bash
docker run -d \
  -p 9090:9090 \
  -v /tmp/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus:latest
```

**2. Configure scrape target:**
```yaml
# /tmp/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'orchestrator'
    static_configs:
      - targets: ['localhost:8000']  # Your metrics endpoint
```

**3. Access metrics:**
```bash
curl http://localhost:9090/api/v1/query?query=remediation_attempts_total
```

### Grafana Setup

**1. Install Grafana:**
```bash
docker run -d -p 3000:3000 grafana/grafana:latest
```

**2. Add Prometheus data source:**
```
URL: http://prometheus:9090
```

**3. Import dashboard:**
```python
# Get dashboard JSON
from self_healing_orchestrator.dashboards import get_grafana_dashboard
import json

dashboard = get_grafana_dashboard()
# Save to Grafana: curl -X POST http://localhost:3000/api/dashboards/db ...
```

### Slack Alerting

**1. Create Slack webhook:**
```bash
# In Slack workspace → Incoming Webhooks → Add New → Copy URL
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR_WEBHOOK_URL"
```

**2. Add to GitHub secrets:**
```
SLACK_WEBHOOK_URL = https://hooks.slack.com/services/...
```

**3. Alerts are sent automatically:**
```
🚨 [CRITICAL] Deployment failed: deploy-001
Severity: critical
Module: RetryEngine
Attempts: 3/3 failed
Action: Creating GitHub issue for human investigation
```

### PagerDuty Integration

**1. Create PagerDuty integration:**
```
Services → New Service → GitHub Actions → Copy Integration Key
```

**2. Add to GitHub secrets:**
```
PAGERDUTY_INTEGRATION_KEY = ...
```

**3. Critical failures trigger incidents automatically**

---

## Troubleshooting

### Credential Not Found

**Error:**
```
CredentialManager: Failed to get orchestrator/github-token from Vault
Error: 404 Not Found
```

**Solution:**
```bash
# Verify secret exists
vault kv get secret/github-token

# Or for GCP
gcloud secrets describe orchestrator-github-token

# Or for AWS
aws secretsmanager describe-secret \
  --secret-id orchestrator/github-token
```

### OIDC Token Expired

**Error:**
```
AssumeRoleWithWebIdentity: Error validating token
```

**Solution:**
- OIDC tokens expire after ~5 minutes (expected)
- Workflow will automatically retry with new token
- If persistent, check token.actions.githubusercontent.com is reachable
- Verify role ARN is correct in GitHub secrets

### Remediation Loop (Infinite Retry)

**Error:**
```
RemediationStep: Max retries exceeded after 3 attempts
```

**Solution:**
```bash
# Check circuit breaker status
python3 -c "
from self_healing_orchestrator.orchestrator import WorkflowOrchestrator
o = WorkflowOrchestrator()
print(o.circuit_breaker.state)  # Should be OPEN if failed
"

# Reset circuit breaker
python3 -c "
from self_healing_orchestrator.orchestrator import WorkflowOrchestrator
o = WorkflowOrchestrator()
o.circuit_breaker.reset()
"

# Check audit trail
cat deployment-report-*.json | jq '.remediation_steps[-1]'
```

### Metrics Endpoint Not Responding

**Error:**
```
curl: (7) Failed to connect to localhost:8000
```

**Solution:**
```bash
# Check if metrics server is running
ps aux | grep metrics_server

# Start metrics server
python3 -m self_healing_orchestrator.monitoring

# Verify it's listening
netstat -tlnp | grep 8000

# Test endpoint
curl http://localhost:8000/metrics

# Export as JSON (for Prometheus)
curl http://localhost:8000/metrics/json
```

### Health Check Failing

**Error:**
```
HealthValidator: Critical check failed: database_connection
```

**Solution:**
```bash
# Run health checks manually
python3 -c "
from self_healing_orchestrator.health_validator import HealthValidator
hv = HealthValidator()
result = hv.validate_all()
print(result)
"

# Check specific check
python3 -c "
from self_healing_orchestrator.health_validator import HealthValidator
hv = HealthValidator()
result = hv.validate_critical_checks()
print(result)
"
```

---

## Best Practices

### 1. Credential Rotation
- [ ] Set up daily rotation (automatic via `rotation_schedule.yml`)
- [ ] Verify rotations in GitHub Actions logs
- [ ] Set alerts for failed rotations

### 2. Audit Trails
- [ ] Archive deployment reports to S3/Cloud Storage
- [ ] Query reports for compliance audits
- [ ] Keep at least 90 days of history

### 3. Monitoring
- [ ] Set up Prometheus scraping (15-second interval)
- [ ] Import Grafana dashboard
- [ ] Configure alerting thresholds:
  - Remediation failure rate > 5%
  - Deployment duration > 5 minutes
  - Health check failures > 1

### 4. Testing
- [ ] Test in staging before production
- [ ] Run manual orchestration locally first
- [ ] Monitor first 5 production deployments closely

### 5. Documentation
- [ ] Document custom remediation steps
- [ ] Keep runbooks updated
- [ ] Share with on-call team

### 6. Security
- [ ] Use OIDC/WIF (never commit tokens)
- [ ] Rotate credentials weekly
- [ ] Restrict GitHub Actions permissions
- [ ] Audit credential access logs

---

## Support

- 📖 **[PROJECT_OVERVIEW.md](../architecture/PROJECT_OVERVIEW.md)** — Architecture deep-dive
- 🔍 **[README.md](../../self_healing/README.md)** — Quick reference
- 💬 **GitHub Issues** — Report bugs
- 🔒 **security@example.com** — Security issues
