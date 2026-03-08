# Operator Setup Automation Helper Guide

**Status**: ✅ Production Ready  
**Type**: Hands-Off Automation  
**Target**: Issue #1384 (5 operator actions)

---

## Overview

The Operator Setup Automation Helper automates the process of completing the 5 required actions in issue #1384. It provides:

- Interactive guided setup workflow
- Automatic secret verification and addition
- Status checking and validation
- Emergency credential recovery procedures
- Immutable audit trail (all actions logged)

---

## 5 Actions Automated

### 1️⃣ Create GitHub Environment
**Action**: `prod-terraform-apply` with required reviewers  
**Automation**: Shows visual guide + links  
**Manual Step**: Complete in GitHub UI (2 minutes)

### 2️⃣ Add Repository Secrets
**Secrets**: AWS_ROLE_TO_ASSUME, AWS_REGION, PROD_TFVARS, GOOGLE_CREDENTIALS, STAGING_KUBECONFIG  
**Automation**: Verifies existing, accepts new values, adds via GitHub CLI  
**Modes**: Interactive prompt or parameter-based

### 3️⃣ Validate terraform.tfvars
**Check**: Verify vpc_id, subnet_ids, and other required variables  
**Automation**: Parse file, validate structure, suggest fixes  
**Output**: Status report

### 4️⃣ Configure Webhook Secret (Optional)
**For**: Graceful AWS Spot spot termination handling  
**Automation**: Optional prompt, adds if provided  
**Fallback**: Can be skipped

### 5️⃣ Setup GCP Secret Manager
**For**: Immutable credential storage and rotation  
**Automation**: Enable API, create service account, assign permissions  
**Requirements**: gcloud CLI + GCP project access

---

## Quick Start

### Check Current Status
```bash
bash scripts/automation/operator-setup-automation.sh check
```

Output shows:
- ✅ Completed actions
- ⚠️  Pending actions
- ❌ Failed actions

### Run Guided Setup
```bash
bash scripts/automation/operator-setup-automation.sh setup
```

Interactive flow:
1. Prompts for each action
2. Validates inputs
3. Adds secrets automatically
4. Performs final verification

### Validate Everything
```bash
bash scripts/automation/operator-setup-automation.sh validate
```

Checks all 5 actions and reports overall status.

---

## Mode Reference

| Mode | Purpose | Interactive |
|------|---------|------------|
| `check` | Display current setup status | No |
| `setup` | Run guided interactive setup | Yes |
| `validate` | Validate all requirements | No |
| `verify-secrets` | Check required secrets only | No |
| `validate-tfvars` | Check terraform.tfvars only | No |
| `emergency` | Credential recovery procedures | Yes |

---

## System Properties

✅ **Immutable**: All actions logged to `.github/workflows/logs/operator-setup-*.log`  
✅ **Ephemeral**: State reset between runs, no persistence  
✅ **Idempotent**: Safe to re-run, detects existing state  
✅ **No-Ops**: Fully driven by CLI/automation  
✅ **Hands-Off**: After secrets added, terraform workflows auto-run

---

## Usage Examples

### Scenario 1: First-Time Setup
```bash
# Check what's missing
bash scripts/automation/operator-setup-automation.sh check

# Run guided setup
bash scripts/automation/operator-setup-automation.sh setup

# Verify everything works
bash scripts/automation/operator-setup-automation.sh validate
```

### Scenario 2: Verify Existing Secrets
```bash
bash scripts/automation/operator-setup-automation.sh verify-secrets
```

Output:
```
✅ Secret found: AWS_ROLE_TO_ASSUME
✅ Secret found: AWS_REGION
⚠️  Secret missing: PROD_TFVARS
```

### Scenario 3: Fix Terraform Configuration
```bash
bash scripts/automation/operator-setup-automation.sh validate-tfvars
```

Shows validation report and suggestions.

### Scenario 4: Emergency Credential Rotation
```bash
bash scripts/automation/operator-setup-automation.sh emergency
```

Guides through:
1. Revoking old credentials
2. Generating new ones
3. Updating secrets
4. Re-triggering workflows

---

## Integration with CI/CD

### Automatic Detection (existing workflow)
- `health-check-secrets.yml`: Runs every 30 minutes
- Detects when all secrets are present
- Triggers `terraform-plan.yml` automatically
- No manual intervention needed

### Approval & Apply
1. Operator updates secret → health check detects
2. Within 30 min: `terraform-plan` auto-runs
3. Operator approves via comment: `⏳ Plan approved`
4. `terraform-apply` auto-runs
5. `post-deployment-validation` auto-runs
6. Infrastructure ready

---

## Troubleshooting

### "GitHub CLI not found"
```bash
# Solution: Install GitHub CLI
# macOS: brew install gh
# Linux: https://cli.github.com
# Windows: https://cli.github.com

# Then authenticate
gh auth login
```

### "Secret missing: PROD_TFVARS"
```bash
# Solution: Manual secret addition
echo "your-value-here" | gh secret set PROD_TFVARS

# Or use setup mode
bash scripts/automation/operator-setup-automation.sh setup
```

### "terraform.tfvars not found"
```bash
# Solution: Copy example and customize
cp terraform/examples/aws-spot/terraform.tfvars.example \
   terraform/examples/aws-spot/terraform.tfvars

# Edit with your values
nano terraform/examples/aws-spot/terraform.tfvars
```

### "gcloud CLI not found"
```bash
# Solution: Install Google Cloud SDK
# https://cloud.google.com/sdk/docs/install

# Then set project
gcloud config set project YOUR_PROJECT_ID
```

---

## Related Issues

- **#1384**: Master Terraform unblock (primary blocker)
- **#1309**: Terraform dry-run (depends on credentials)
- **#1346**: AWS OIDC setup
- **#268, #379**: Environment protection

---

## Next Steps After Setup

Once all 5 actions complete:

1. **Within 30 min**: Health check detects secrets
2. **Automatically**: `terraform-plan` runs
3. **Show up on**: Issue with plan artifacts
4. **You approve**: Comment `⏳ Plan approved`
5. **Automatically**: `terraform-apply` runs
6. **Then**: Post-deployment validation
7. **Finally**: Infrastructure operational

---

## Monitoring

### Check Workflow Status
```bash
# Watch terraform workflows
gh workflow run terraform-plan.yml
gh run watch

# View plan output
gh run list --workflow=terraform-plan.yml --limit 1
```

### View Logs
```bash
# Check operator automation logs
tail -f .github/workflows/logs/operator-setup-*.log

# Check terraform workflow logs
gh run view <run-id> --log
```

---

## Configuration

### GitHub Secrets Location
Repository Settings → Secrets and Variables → Actions

### terraform.tfvars Location
`terraform/examples/aws-spot/terraform.tfvars`

### Required Environment
- GitHub CLI (`gh`) — authenticated
- Git — for version control
- AWS CLI — for AWS credential verification (optional)
- gcloud CLI — for GCP GSM setup (optional)

---

## Support

**For questions about**:
- Operator actions: See issue #1384
- Terraform deployment: See `PHASE_P4_DEPLOYMENT_READINESS.md`
- Credential setup: See [GCP_GSM_INTEGRATION_GUIDE.md](GCP_GSM_INTEGRATION_GUIDE.md)
- Hands-off automation: See [HANDS_OFF_AUTOMATION_RUNBOOK.md](HANDS_OFF_AUTOMATION_RUNBOOK.md)

---

**Status**: 🟢 Ready to Use  
**Last Updated**: March 8, 2026  
**Maintained By**: Automation Framework
