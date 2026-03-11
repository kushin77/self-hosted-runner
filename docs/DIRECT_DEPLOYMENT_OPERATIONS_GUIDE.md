# 📖 Direct Deployment Operations Guide

**Date**: 2026-03-10  
**Version**: 1.0  
**Architecture**: Immutable + Ephemeral + Idempotent + No-Ops + Hands-Off

---

## 🎯 Quick Start

### Deploy Staging Environment
```bash
cd /home/akushnir/self-hosted-runner
./scripts/direct-deploy-production.sh staging
```

### Deploy Production Environment
```bash
cd /home/akushnir/self-hosted-runner
./scripts/direct-deploy-production.sh production
```

### Validate Credential System
```bash
bash infra/credentials/validate-credentials.sh --verbose
```

### Check Deployment Audit Trail
```bash
tail -f logs/direct-deployment-audit-$(date +%Y%m%d).jsonl
```

---

## 🔐 Credential Management

### Understanding the 4-Tier System

**Tier 1: Google Secret Manager (Primary)**
- Fastest (~100ms)
- GCP-native
- Best for cloud deployments
- Check with: `gcloud secrets list`

**Tier 2: HashiCorp Vault (Secondary)**
- Universal store
- Multi-cloud support
- Slower (~500ms)
- Check with: `vault kv list secret/`

**Tier 3: AWS KMS + Environment (Tertiary)**
- Emergency fallback
- Encrypted in memory
- Check with: `echo $CREDENTIAL_NAME_ENCRYPTED`

**Tier 4: Local Emergency Keys (Break-Glass)**
- Last resort only
- Stored in `.credentials/` (never committed)
- Check with: `ls -la .credentials/`

### Loading a Credential Manually
```bash
# Load credential from best available source
source infra/credentials/load-credential.sh "gcp-service-account-key"
echo "$CREDENTIAL" | jq .  # View loaded credential (example)
```

### Creating a New Credential

**Option A: Google Secret Manager**
```bash
# Create secret
gcloud secrets create my-secret \
  --replication-policy="automatic" \
  --data-file=mysecret.txt

# Grant access to service account
gcloud secrets add-iam-policy-binding my-secret \
  --member=serviceAccount:my-sa@project.iam.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor

# Verify access
gcloud secrets versions access latest --secret="my-secret"
```

**Option B: HashiCorp Vault**
```bash
# Create secret in Vault
vault kv put secret/my-secret value=@mysecret.txt

# Verify access
vault kv get secret/my-secret
```

**Option C: AWS KMS + Environment**
```bash
# Encrypt credential
ENCRYPTED=$(aws kms encrypt \
  --key-id "alias/my-key" \
  --plaintext "fileb://mysecret.txt" \
  --query 'CiphertextBlob' \
  --output text)

# Set environment variable
export MY_SECRET_ENCRYPTED="$ENCRYPTED"

# Verify it loads
source infra/credentials/load-credential.sh "my-secret"
```

**Option D: Local Emergency Key**
```bash
# Create local key (never commit to git)
mkdir -p .credentials
chmod 700 .credentials
echo "my-secret-value" > .credentials/my-secret.key
chmod 600 .credentials/my-secret.key

# Verify .credentials is in .gitignore
grep ".credentials/" .gitignore || echo ".credentials/" >> .gitignore
```

---

## 🚀 Deployment Operations

### Standard Deployment Workflow
```bash
# 1. Navigate to project root
cd /home/akushnir/self-hosted-runner

# 2. Ensure you're on main branch (required)
git checkout main
git pull origin main

# 3. Validate all credentials accessible
bash infra/credentials/validate-credentials.sh --verbose

# 4. Execute deployment
./scripts/direct-deploy-production.sh staging

# 5. Monitor the audit trail
tail -f logs/direct-deployment-audit-*.jsonl

# 6. Verify infrastructure health
gcloud compute instances list
gcloud run services list
```

### Rolling Back a Deployment
```bash
# Option 1: Restore previous git commit
git revert <commit-sha>
git push origin main

# Option 2: Terraform destroy and redeploy
cd terraform/
terraform destroy -auto-approve -var="environment=staging"
./scripts/direct-deploy-production.sh staging

# Note: Check audit trail before rollback
tail logs/direct-deployment-audit-*.jsonl | grep "deploy-.*staging"
```

### Monitoring Active Deployments
```bash
# View last 100 lines of audit trail
tail -100 logs/direct-deployment-audit-$(date +%Y%m%d).jsonl | jq .

# Monitor in real-time
tail -f logs/direct-deployment-audit-$(date +%Y%m%d).jsonl | jq .

# Filter by event type
jq 'select(.event == "stage_terraform_apply")' logs/direct-deployment-audit-*.jsonl

# Count by status
jq -r '.status' logs/direct-deployment-audit-*.jsonl | sort | uniq -c
```

---

## 🏗️ Infrastructure Management

### Viewing Terraform State
```bash
cd terraform/

# Show current state
terraform state list

# Show specific resource
terraform state show 'google_compute_instance.app_server'

# Show state summary
terraform state list | wc -l  # Total resources
```

### Planning Infrastructure Changes
```bash
cd terraform/

# Generate plan file
terraform plan -var="environment=staging" -out=tfplan

# Review plan (non-destructive)
terraform show tfplan

# Apply plan (never use auto-approve in manual testing)
terraform apply tfplan
```

### Manual Infrastructure Modifications
```bash
# Import external resource
terraform import google_compute_instance.manual-server BASE64_BLOB_REDACTED

# Taint resource for recreation
terraform taint google_compute_instance.app_server

# Force destroy on next apply
terraform apply -replace='google_compute_instance.app_server'
```

---

## 📊 Monitoring & Observability

### Cloud Run Services
```bash
# List deployed services
gcloud run services list --region=us-central1

# Get service details
gcloud run services describe portal-backend --region=us-central1

# View recent deployments
gcloud run services describe portal-backend --region=us-central1 \
  --format="value(status.traffic[].revision.name)"

# Check service logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=portal-backend" \
  --limit 50 --format json
```

### Cloud SQL Database
```bash
# List instances
gcloud sql instances list

# Get instance status
gcloud sql instances describe portal-db

# Check backups
gcloud sql backups list --instance=portal-db

# Create manual backup
gcloud sql backups create --instance=portal-db
```

### Cloud Monitoring Dashboards
```bash
# List dashboards
gcloud monitoring dashboards list

# Create dashboard from JSON
gcloud monitoring dashboards create --config-from-file=dashboard.json

# Delete dashboard
gcloud monitoring dashboards delete $DASHBOARD_ID
```

### Viewing Metrics
```bash
# CPU utilization (Cloud Run)
gcloud monitoring time-series list \
  --filter='metric.type="run.googleapis.com/request_latencies"' \
  --interval-start-time=2h --format=json

# Request rate
gcloud monitoring time-series list \
  --filter='metric.type="run.googleapis.com/request_count"' \
  --format=json
```

---

## 🔧 Troubleshooting

### Credential Loading Fails
```bash
# Test each tier individually
echo "=== Testing GSM ==="
gcloud secrets versions access latest --secret="gcp-service-account-key" --project=$GCP_PROJECT_ID

echo "=== Testing Vault ==="
vault kv get secret/gcp-service-account-key

echo "=== Testing KMS ==="
echo $GCP_SERVICE_ACCOUNT_KEY_ENCRYPTED | base64 -d | \
  aws kms decrypt --ciphertext-blob fileb:///dev/stdin --region us-east-1 --query 'Plaintext'

echo "=== Testing Local Key ==="
cat .credentials/gcp-service-account-key.key
```

### Terraform Plan Fails
```bash
# Verify credentials are loaded
echo $GCP_SERVICE_ACCOUNT_KEY | jq .

# Check Terraform provider config
terraform providers

# Validate Terraform syntax
terraform validate

# Debug with verbose output
TF_LOG=DEBUG terraform plan -var="environment=staging"
```

### Deployment Script Hangs
```bash
# Kill hanging process
pkill -f "direct-deploy-production.sh"

# Check resource status
gcloud compute instances list
gcloud run services list

# Review last audit entry
tail -1 logs/direct-deployment-audit-*.jsonl | jq .

# Retry deployment
./scripts/direct-deploy-production.sh staging
```

### Health Checks Failing
```bash
# Test backend connectivity
curl -v https://api.portal-staging.nexusshield.cloud/health

# Check Cloud Run service logs
gcloud logging read "resource.type=cloud_run_revision" \
  --format="(timestamp,jsonPayload.message)" \
  --limit=50

# Verify database connectivity
gcloud sql connect portal-db-staging --dry-run

# Check load balancer status
gcloud compute backend-services get-health portal-backend
```

### Audit Trail Not Recording
```bash
# Check file permissions
ls -la logs/direct-deployment-audit-*.jsonl

# Verify git access
git add logs/
git status

# Manually commit audit log
git commit -m "audit: manual audit trail commit"

# Check audit log format
jq . logs/direct-deployment-audit-*.jsonl | head -20
```

---

## 🛟 Emergency Procedures

### Break-Glass Access
**Use ONLY in critical incidents**

```bash
# 1. Identify needed credential
CREDENTIAL_NAME="postgres-password"

# 2. Load from break-glass (local key)
CREDENTIAL=$(bash infra/credentials/break-glass-access.sh "$CREDENTIAL_NAME" "INC-12345")

# 3. Use credential (temporary only)
psql -h $POSTGRES_HOST -U $POSTGRES_USER -p 5432 <<< "$CREDENTIAL"

# 4. Create incident ticket immediately
# Create GitHub issue: "Emergency credential access for [credential name]"

# 5. Rotate credential within 1 hour
bash infra/credentials/rotate-credentials.sh

# 6. Audit trail automatically logged to logs/break-glass-audit.jsonl
```

### Emergency Rollback
```bash
# Stop running deployment
pkill -f "direct-deploy-production.sh"

# Revert to previous commit
git revert HEAD
git push origin main

# Redeploy previous version
./scripts/direct-deploy-production.sh staging

# Notify team
# (Post in #incidents Slack channel or create GitHub issue)
```

### Service Outage Recovery
```bash
# 1. Diagnose issue
curl -v https://api.portal-staging.nexusshield.cloud/health

# 2. Check recent logs
tail -100 logs/direct-deployment-audit-*.jsonl | jq 'select(.status=="failed")'

# 3. Identify root cause
gcloud logging read "severity>=ERROR" --limit 50 --format json

# 4. If infrastructure issue:
cd terraform/
terraform destroy -auto-approve
sleep 30
./scripts/direct-deploy-production.sh staging

# 5. If credential issue:
bash infra/credentials/validate-credentials.sh --verbose

# 6. If code issue:
git revert <problematic-commit>
./scripts/direct-deploy-production.sh staging
```

---

## 📝 Maintenance Tasks

### Daily
- Monitor deployment audit trail
- Check system health (dashboard)
- Verify backup completion

### Weekly
- Review audit logs for errors
- Validate credential access (all 4 tiers)
- Test backup restoration

### Monthly
- Rotate all credentials
- Review and update documentation
- Verify disaster recovery procedures
- Check compliance requirements

### Quarterly
- Full security audit
- Load testing validation
- Documentation review
- Architecture assessment

---

## 📞 Support

### Getting Help
1. Check audit logs: `tail -100 logs/direct-deployment-audit-*.jsonl`
2. Review troubleshooting section above
3. Validate credential system: `bash infra/credentials/validate-credentials.sh`
4. Check Terraform state: `cd terraform && terraform state list`
5. Review git history: `git log --oneline | head -20`

### Reporting Issues
Create GitHub issue with:
- Error message (from logs)
- Deployment environment (staging/production)
- Audit trail entries (from JSONL)
- Git commit SHA
- Timestamp of incident

---

## ✅ Operations Checklist

Before any deployment:
- [ ] On main branch (`git branch | grep main`)
- [ ] All credentials validated (`bash infra/credentials/validate-credentials.sh`)
- [ ] Terraform state clean (`terraform state list`)
- [ ] No pending changes (`git status --short`)
- [ ] Recent logs reviewed (`tail logs/direct-deployment-audit-*.jsonl`)
- [ ] Backup exists (`gcloud sql backups list`)

After deployment:
- [ ] Audit log written (`tail logs/direct-deployment-audit-*.jsonl`)
- [ ] Health checks passed (`curl .../health`)
- [ ] Monitoring dashboards active
- [ ] Git commit recorded (`git log -1`)
- [ ] Incident created if failed
- [ ] Team notified if critical

---

**Version**: 1.0  
**Last Updated**: 2026-03-10  
**Maintainer**: DevOps Team  
**Status**: ✅ Production Ready
