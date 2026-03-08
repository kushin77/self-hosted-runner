# À la carte Deployment - Quick Start (5 minutes)

## TL;DR

Deploy infrastructure components selectively with immutable audit logs:

```bash
# List components
python3 -m deployment.alacarte --list

# Deploy full suite
python3 -m deployment.alacarte --all

# Deploy by category
python3 -m deployment.alacarte --category security
python3 -m deployment.alacarte --category credentials
python3 -m deployment.alacarte --category automation

# Custom deployment
python3 -m deployment.alacarte --deploy remove-embedded-secrets migrate-to-gsm

# Dry-run (plan only)
python3 -m deployment.alacarte --all --dry-run
```

## Available Components

```
Security:
  • remove-embedded-secrets

Credentials (pick one or all):
  • migrate-to-gsm      (Google Secret Manager)
  • migrate-to-vault    (HashiCorp Vault)
  • migrate-to-kms      (AWS KMS)

Automation:
  • setup-dynamic-credential-retrieval
  • setup-credential-rotation

Healing:
  • activate-rca-autohealer  (Already deployed v2.0)
```

## GitHub Actions (Recommended for Production)

```bash
# Full suite (all components)
gh workflow run 01-alacarte-deployment.yml -f deployment_type=full-suite

# Security only
gh workflow run 01-alacarte-deployment.yml -f deployment_type=security

# Credentials only
gh workflow run 01-alacarte-deployment.yml -f deployment_type=credentials

# Automation only
gh workflow run 01-alacarte-deployment.yml -f deployment_type=automation

# Custom components
gh workflow run 01-alacarte-deployment.yml \
  -f deployment_type=custom \
  -f custom_components='remove-embedded-secrets,migrate-to-gsm'

# Dry-run (plan only)
gh workflow run 01-alacarte-deployment.yml -f dry_run=true

# Skip approval (auto-execute)
gh workflow run 01-alacarte-deployment.yml -f deployment_type=full-suite -f skip_approval=true
```

## What You Get

✅ **Immutable Audit Trail** - All operations logged
✅ **Safe Re-runs** - Idempotent execution
✅ **Auto Cleanup** - Ephemeral resources
✅ **Zero Manual Steps** - Fully automated
✅ **Secure Credentials** - GSM/Vault/KMS injection

## Architecture

```
Component Selection
      ↓
Dependency Resolution
      ↓
Credential Injection
      ↓
Execute in Order
      ↓
Immutable Audit Log
      ↓
GitHub Issue Update
```

## Required Secrets

Set these in GitHub settings:

```
GCP_PROJECT_ID=your-gcp-project
VAULT_ADDR=https://vault.example.com
AWS_ACCOUNT_ID=123456789
AWS_REGION=us-east-1
```

## Audit Logs

Check deployment results:

```bash
# List all deployments
ls -la .deployment-audit/

# View deployment log
cat .deployment-audit/deployment_alacarte-*.log

# View audit trail (JSON)
cat .deployment-audit/deployment_alacarte-*.jsonl | jq

# View deployment summary
cat .deployment-audit/deployment_alacarte-*_manifest.json | jq
```

## Monitor Progress

```bash
# Check GitHub Actions
gh run list --workflow 01-alacarte-deployment.yml

# Follow specific run
gh run view <run-id> --log

# Track via GitHub issues
gh issue list --label deployment
```

## Troubleshooting

**Deployment fails:** Check `.deployment-audit/` logs for details
**Missing secrets:** Configure GCP_PROJECT_ID, VAULT_ADDR, AWS_ACCOUNT_ID
**Dry-run only:** Pass `--dry-run` flag to plan without execution
**Specific component:** Use `--deploy component-id` to run single component

## Documentation

- Full guide: `ALACARTE_DEPLOYMENT_GUIDE.md`
- Summary: `ALACARTE_DEPLOYMENT_SUMMARY.md`
- This quick start: `ALACARTE_QUICK_START.md`

## Examples

### Example 1: Test with dry-run
```bash
python3 -m deployment.alacarte --deploy remove-embedded-secrets --dry-run
```

### Example 2: Deploy security components
```bash
python3 -m deployment.alacarte --deploy remove-embedded-secrets
```

### Example 3: Deploy all credentials to GSM
```bash
python3 -m deployment.alacarte --deploy remove-embedded-secrets migrate-to-gsm setup-dynamic-credential-retrieval
```

### Example 4: Full production deployment
```bash
gh workflow run 01-alacarte-deployment.yml -f deployment_type=full-suite -f skip_approval=false
```

### Example 5: Daily scheduled check
```bash
# Scheduled automatically at 3 AM UTC daily
# Or manually trigger:
gh workflow run 01-alacarte-deployment.yml -f deployment_type=full-suite
```

## Status

🚀 **Production Ready** - Deploy now

See #1958 for deployment details.
