# 🚀 Deployment Field Auto-Provisioning - Quick Start

**Date:** 2026-03-09  
**Status:** Production Ready  
**Time to Deploy:** 5-10 minutes

---

## ⚡ 30-Second Overview

You have 3 critical deployment fields that MUST be populated before deployment:

| Field | Example | Required |
|-------|---------|----------|
| VAULT_ADDR | https://vault.company.com:8200 | ✅ YES |
| VAULT_ROLE | github-actions-prod | ✅ YES |
| AWS_ROLE_TO_ASSUME | arn:aws:iam::987654321098:role/github-actions | ✅ YES |
| GCP_WORKLOAD_IDENTITY_PROVIDER | projects/my-project/locations/global/... | ✅ YES |

**Solution:** This system auto-populates them from GSM/Vault/KMS. You don't have to manually fill them.

---

## 📋 Prerequisites

**One-time setup (5 min):**

1. Add credentials to your provider (GSM/Vault/KMS)
2. Verify credentials are accessible from GitHub Actions
3. Done!

---

## 🔧 Step 1: Add Credentials to Provider

Choose ONE provider:

### Option A: Google Secret Manager (Recommended)

```bash
# Add to GSM
export GCP_PROJECT_ID=my-project

echo "https://vault.company.com:8200" | \
  gcloud secrets versions add deployment-fields-VAULT_ADDR --data-file=-

echo "github-actions-prod" | \
  gcloud secrets versions add deployment-fields-VAULT_ROLE --data-file=-

echo "arn:aws:iam::987654321098:role/github-actions" | \
  gcloud secrets versions add deployment-fields-AWS_ROLE_TO_ASSUME --data-file=-

echo "projects/my-project/locations/global/workloadIdentityPools/github/providers/github" | \
  gcloud secrets versions add deployment-fields-GCP_WORKLOAD_IDENTITY_PROVIDER --data-file=-

# Verify
gcloud secrets list | grep deployment-fields
```

### Option B: HashiCorp Vault

```bash
# Add to Vault
export VAULT_ADDR=https://vault.internal:8200

vault kv put secret/deployment/fields/VAULT_ADDR \
  value=https://vault.company.com:8200

vault kv put secret/deployment/fields/VAULT_ROLE \
  value=github-actions-prod

vault kv put secret/deployment/fields/AWS_ROLE_TO_ASSUME \
  value=arn:aws:iam::987654321098:role/github-actions

vault kv put secret/deployment/fields/GCP_WORKLOAD_IDENTITY_PROVIDER \
  value=projects/my-project/locations/global/workloadIdentityPools/github/providers/github

# Verify
vault kv list secret/deployment/fields/
```

### Option C: AWS Secrets Manager

```bash
# Add to Secrets Manager
aws secretsmanager create-secret --name deployment/VAULT_ADDR \
  --secret-string "https://vault.company.com:8200"

aws secretsmanager create-secret --name deployment/VAULT_ROLE \
  --secret-string "github-actions-prod"

aws secretsmanager create-secret --name deployment/AWS_ROLE_TO_ASSUME \
  --secret-string "arn:aws:iam::987654321098:role/github-actions"

aws secretsmanager create-secret --name deployment/GCP_WORKLOAD_IDENTITY_PROVIDER \
  --secret-string "projects/my-project/locations/global/workloadIdentityPools/github/providers/github"

# Verify
aws secretsmanager list-secrets --filters Key=name,Values=deployment
```

---

## 💾 Step 2: Discover Current State

```bash
# See where fields are currently sourced from
./scripts/discover-deployment-fields.sh

# Or as JSON for scripting
./scripts/discover-deployment-fields.sh json

# Or as Markdown for documentation
./scripts/discover-deployment-fields.sh markdown
```

**Output shows:**
- ✅ Which fields are configured
- ⚠️ Which fields are still placeholders
- 📍 Where each field is sourced from

---

## 🔄 Step 3: Auto-Provision Fields

### Method 1: Using Make (Recommended)

```bash
# Simplest: one command
make -f Makefile.provisioning provision-fields

# Or specific provider
PREFERRED_PROVIDER=gsm make -f Makefile.provisioning provision-fields

# Dry-run (test without changes)
make -f Makefile.provisioning provision-fields-dry

# View all options
make -f Makefile.provisioning provision-help
```

### Method 2: Direct Script

```bash
# Standard provisioning
./scripts/auto-provision-deployment-fields.sh

# Use specific provider
PREFERRED_PROVIDER=vault ./scripts/auto-provision-deployment-fields.sh

# Dry-run mode
./scripts/auto-provision-deployment-fields.sh --dry-run

# Verbose output
./scripts/auto-provision-deployment-fields.sh
```

### Method 3: GitHub Actions

```bash
# Manual trigger
gh workflow run auto-provision-fields.yml --ref main

# Schedule (automatic - runs daily at 4 AM UTC)
# See: .github/workflows/auto-provision-fields.yml
```

---

## ✔️ Step 4: Verify Provisioning

```bash
# Standard verification
make -f Makefile.provisioning verify-provisioning

# Or direct script
./scripts/verify-deployment-provisioning.sh

# Verbose (for debugging)
./scripts/verify-deployment-provisioning.sh --verbose
```

**Checks:**
- ✅ All 4 fields are set
- ✅ No placeholder values remain
- ✅ Providers are accessible
- ✅ Formats are valid (ARNs, URLs, paths)
- ✅ Vault/AWS/GCP can authenticate

---

## 🚀 Step 5: Deploy!

```bash
# Full deployment with provisioning
make -f Makefile.provisioning deploy-with-fields

# Or components separately
make -f Makefile.provisioning provision-fields
make -f Makefile.provisioning verify-provisioning
make deploy                    # Your normal deployment

# Or in actions
./scripts/auto-provision-deployment-fields.sh
./scripts/verify-deployment-provisioning.sh
docker-compose -f docker-compose.prod.yml up -d
```

---

## 📊 Complete Workflow

```
┌─────────────────────────────────────────────────────────┐
│ 1. Add secrets to GSM/Vault/KMS                         │
│    (One-time setup, 5 min)                              │
└────────────────┬─────────────────────────────────────────┘
                 │
┌────────────────▼─────────────────────────────────────────┐
│ 2. Discover fields: scripts/discover-deployment-fields  │
│    (Check what's available, 30 sec)                      │
└────────────────┬─────────────────────────────────────────┘
                 │
┌────────────────▼─────────────────────────────────────────┐
│ 3. Auto-provision: make provision-fields               │
│    (Auto-fetch & populate, 1-2 min)                     │
└────────────────┬─────────────────────────────────────────┘
                 │
┌────────────────▼─────────────────────────────────────────┐
│ 4. Verify: make verify-provisioning                    │
│    (Validate all fields, 1 min)                         │
└────────────────┬─────────────────────────────────────────┘
                 │
┌────────────────▼─────────────────────────────────────────┐
│ 5. Deploy: make deploy                                  │
│    (Your standard deployment, ~5 min)                   │
└─────────────────────────────────────────────────────────┘
```

---

## 🔍 Troubleshooting

### ❌ "Field not found"
```bash
# Check if credential was added to provider
gcloud secrets list | grep deployment-fields    # GSM
vault kv list secret/deployment/fields/         # Vault
aws secretsmanager list-secrets                 # AWS

# Add missing credential and try again
```

### ❌ "Cannot reach provider"
```bash
# Test connectivity to provider
curl https://vault.company.com:8200/v1/sys/health    # Vault
gcloud auth list                                       # GSM (check auth)
aws sts get-caller-identity                           # AWS (check auth)

# Verify firewall/network allows GitHub Actions
```

### ❌ "Invalid ARN format"
```bash
# Verify AWS role ARN format
# Must be: arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME
# Example: arn:aws:iam::987654321098:role/github-actions

# Update in credential provider and re-run provisioning
```

### ❌ "GCP WIF format invalid"
```bash
# Verify GCP WIF provider format
# Must be: projects/PROJECT/locations/global/workloadIdentityPools/POOL/providers/PROVIDER
# Example: projects/my-project/locations/global/workloadIdentityPools/github/providers/github

# Update in credential provider and re-run provisioning
```

---

## 📊 Monitor Provisioning

```bash
# View audit trail (all operations)
tail -f logs/deployment-provisioning-audit.jsonl

# View failed operations only
grep '"status":"failed"' logs/deployment-provisioning-audit.jsonl

# Parse as readable JSON
cat logs/deployment-provisioning-audit.jsonl | jq .

# Or use make target
make -f Makefile.provisioning audit-trail
make -f Makefile.provisioning audit-trail-failed
```

---

## 🧪 Run Tests

```bash
# Integration tests (validates all components)
bash tests/test-provisioning-integration.sh

# Verbose output
bash tests/test-provisioning-integration.sh --verbose
```

---

## 📚 Detailed Documentation

- **Full Guide:** [docs/DEPLOYMENT_FIELD_AUTO_PROVISIONING.md](docs/DEPLOYMENT_FIELD_AUTO_PROVISIONING.md)
- **Status Report:** [DEPLOYMENT_FIELD_AUTO_PROVISIONING_COMPLETE.md](DEPLOYMENT_FIELD_AUTO_PROVISIONING_COMPLETE.md)
- **Makefile Help:** `make -f Makefile.provisioning provision-help`

---

## ❓ FAQ

**Q: Do I have to use all 3 providers?**  
A: No. The system tries them in order (GSM → Vault → KMS). Just add to ONE and it will work.

**Q: How often does provisioning happen?**  
A: Depends on how you trigger it:
  - Manual: When you run `make provision-fields`
  - Scheduled: Daily at 4 AM UTC (via GitHub Actions)
  - Pre-deployment: Before each deployment if you add it to pipeline

**Q: Can I preview what will be provisioned?**  
A: Yes! Use dry-run mode: `make -f Makefile.provisioning provision-fields-dry`

**Q: What if a field is still placeholder after provisioning?**  
A: The credential provider doesn't have the actual value. Update the secret in GSM/Vault/KMS and re-run.

**Q: Is it safe to run provisioning multiple times?**  
A: Yes! It's idempotent (safe to run repeatedly). Each run is logged for audit trail.

**Q: How are secrets protected?**  
A: Secrets are NEVER stored in git. They're only in:
  - Credential providers (GSM/Vault/KMS)
  - GitHub Actions secrets (encrypted)
  - Systemd environment (process-scoped)

---

## ✅ Success Checklist

Before deploying to production:

- [ ] Credentials added to GSM/Vault/KMS
- [ ] `./scripts/discover-deployment-fields.sh` shows fields are found
- [ ] `make provision-fields` runs without errors
- [ ] `make verify-provisioning` passes all checks
- [ ] Audit trail shows successful provisioning
- [ ] All 4 fields are non-placeholder values
- [ ] Ready to deploy!

---

## 🎯 Next Steps

1. **Now:** Pick a credential provider and add your 4 secrets
2. **Then:** Run `make -f Makefile.provisioning discover-fields`
3. **Then:** Run `make -f Makefile.provisioning provision-fields`
4. **Then:** Run `make -f Makefile.provisioning verify-provisioning`
5. **Finally:** Deploy with confidence!

---

**Questions?** See [docs/DEPLOYMENT_FIELD_AUTO_PROVISIONING.md](docs/DEPLOYMENT_FIELD_AUTO_PROVISIONING.md) for comprehensive guide.

**Issues?** Check audit trail: `grep -i error logs/deployment-provisioning-audit.jsonl`

---

**Time to Deploy:** ~15 minutes (including setup)  
**Status:** ✅ Production Ready  
**Last Updated:** 2026-03-09
