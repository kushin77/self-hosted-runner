# À la carte Deployment Orchestrator - Complete Guide

## Overview

The **à la carte deployment orchestrator** provides modular, selective deployment of infrastructure components with enterprise-grade guarantees:

- ✅ **Immutable**: All deployments logged to append-only audit trails (`.deployment-audit/`)
- ✅ **Idempotent**: Safe to re-run deployments multiple times without side effects
- ✅ **Ephemeral**: Temporary files auto-cleaned after deployment
- ✅ **No-Ops**: Fully automated execution with zero manual steps required
- ✅ **Secure**: Credentials injected via GSM/Vault/KMS using OIDC and Workload Identity Federation

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│         GitHub Actions Workflow Dispatch / Schedule               │
└────────────────────────┬────────────────────────────────────────┘
                         │
        ┌────────────────┴────────────────┐
        │                                  │
    ┌───▼────┐                      ┌─────▼──────┐
    │  Init   │                      │  Validate  │
    └───┬────┘                      └─────┬──────┘
        │                                  │
        └────────────────┬─────────────────┘
                         │
                    ┌────▼──────────┐
                    │ (Approval)    │─── Optional manual gate
                    └────┬──────────┘
                         │
        ┌────────────────▼────────────────┐
        │   DeploymentOrchestrator        │
        │  - Resolve dependencies         │
        │  - Inject credentials (GSM/KMS) │
        │  - Execute components in order  │
        │  - Log to immutable audit trail │
        │  - Create GitHub issues         │
        └────────────────┬────────────────┘
                         │
        ┌────────────────┴────────────────┐
        │                                  │
    ┌───▼────┐                      ┌─────▼──────┐
    │Component│                      │ Validation │
    │Execution│                      │   Steps    │
    └───┬────┘                      └─────┬──────┘
        │                                  │
        └────────────────┬─────────────────┘
                         │
        ┌────────────────▼────────────────┐
        │ Complete & Cleanup              │
        │  - Update GitHub issue          │
        │  - Upload audit logs            │
        │  - Clean ephemeral resources    │
        └────────────────────────────────┘
```

## Available Components

### Security: Remove Embedded Secrets
- **Component ID**: `remove-embedded-secrets`
- **Status**: Ready
- **Purpose**: Scan and remove hardcoded secrets from repository history
- **Category**: Security
- **Critical**: Yes
- **Auto-Remediate**: No

### Credentials: Secret Migration

#### Google Secret Manager (GSM)
- **Component ID**: `migrate-to-gsm`
- **Dependencies**: `remove-embedded-secrets`
- **Purpose**: Migrate secrets to Google Secret Manager with OIDC integration
- **Critical**: Yes

#### HashiCorp Vault
- **Component ID**: `migrate-to-vault`
- **Dependencies**: `remove-embedded-secrets`
- **Purpose**: Migrate secrets to HashiCorp Vault with JWT auth
- **Critical**: Yes

#### AWS KMS
- **Component ID**: `migrate-to-kms`
- **Dependencies**: `remove-embedded-secrets`
- **Purpose**: Migrate secrets to AWS KMS with Workload Identity Federation
- **Critical**: Yes

### Automation: Dynamic Credential Retrieval & Rotation

#### Setup Dynamic Retrieval
- **Component ID**: `setup-dynamic-credential-retrieval`
- **Dependencies**: At least one credential migration component
- **Purpose**: Configure dynamic credential retrieval for workflows
- **Critical**: Yes

#### Setup Credential Rotation
- **Component ID**: `setup-credential-rotation`
- **Dependencies**: `setup-dynamic-credential-retrieval`
- **Purpose**: Setup automated credential rotation (daily at 2 AM UTC)
- **Critical**: Yes
- **Auto-Remediate**: Yes

### Healing: RCA-Driven Auto-Healer

#### Activate RCA Auto-Healer
- **Component ID**: `activate-rca-autohealer`
- **Dependencies**: None (already deployed)
- **Purpose**: Activate RCA-driven auto-healer for workflow failure recovery
- **Auto-Remediate**: Yes
- **Status**: ✅ Already deployed (v2.0.0)

## Deployment Modes

### 1. Full Suite (Recommended for Initial Setup)
Deploy all components in dependency order. Requires approximately 30-45 minutes.

```bash
gh workflow run 01-alacarte-deployment.yml \
  -f deployment_type=full-suite \
  -f skip_approval=false
```

### 2. Security Only
Deploy just the secret remediation and credential migration components.

```bash
gh workflow run 01-alacarte-deployment.yml \
  -f deployment_type=security \
  -f skip_approval=false
```

### 3. Credentials Only
Deploy credential migrations to GSM/Vault/KMS.

```bash
gh workflow run 01-alacarte-deployment.yml \
  -f deployment_type=credentials \
  -f skip_approval=false
```

### 4. Automation Only
Deploy dynamic retrieval and rotation automation.

```bash
gh workflow run 01-alacarte-deployment.yml \
  -f deployment_type=automation \
  -f skip_approval=false
```

### 5. Healing Only
Activate RCA-driven auto-healer (already deployed).

```bash
gh workflow run 01-alacarte-deployment.yml \
  -f deployment_type=healing \
  -f skip_approval=true
```

### 6. Custom Selection
Deploy specific components in custom order.

```bash
gh workflow run 01-alacarte-deployment.yml \
  -f deployment_type=custom \
  -f custom_components="remove-embedded-secrets,migrate-to-gsm,setup-credential-rotation" \
  -f skip_approval=false
```

### 7. Dry-Run Mode
Plan deployment without making actual changes.

```bash
gh workflow run 01-alacarte-deployment.yml \
  -f deployment_type=full-suite \
  -f dry_run=true \
  -f skip_approval=true
```

## Local Deployment

For testing or offline deployment:

```bash
python3 -m deployment.alacarte --help
```

### List Available Components
```bash
python3 -m deployment.alacarte --list
```

### Deploy by Category
```bash
python3 -m deployment.alacarte --category security
python3 -m deployment.alacarte --category credential
python3 -m deployment.alacarte --category automation
```

### Deploy Specific Components
```bash
python3 -m deployment.alacarte --deploy remove-embedded-secrets migrate-to-gsm
```

### Deploy All Components
```bash
python3 -m deployment.alacarte --all
```

### Dry-Run Mode
```bash
python3 -m deployment.alacarte --deploy remove-embedded-secrets --dry-run
```

## Credential Management

### Architecture

The orchestrator supports **three-layer credential management**:

```
┌─────────────────────────────────────────┐
│   Layer 1: GitHub OIDC Token            │
│   (Short-lived, auto-refreshed)          │
└────────────────┬────────────────────────┘
                 │
        ┌────────▼─────────┐
        │  (OIDC Exchange)  │
        └────────┬─────────┘
                 │
  ┌──────────────┼──────────────┐
  │              │              │
  ▼              ▼              ▼
GSM            Vault           KMS
Layer 2:       Layer 2:        Layer 2:
Google Secret  HashiCorp       AWS KMS
Manager        Vault           (WIF Auth)

(All with OIDC / Workload Identity Federation)
```

### Configuration

Set required environment variables or repository secrets:

```bash
# GCP / Google Secret Manager
export GCP_PROJECT_ID="your-gcp-project"
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"

# HashiCorp Vault
export VAULT_ADDR="https://vault.example.com"
export VAULT_NAMESPACE="your-namespace"

# AWS KMS
export AWS_ACCOUNT_ID="123456789"
export AWS_REGION="us-east-1"
export AWS_ROLE_ARN="arn:aws:iam::account:role/github-actions"

# GitHub Token (automatically provided)
# export GITHUB_TOKEN="..."
```

## Audit Trail

All deployments are logged immutably to `.deployment-audit/`:

```
.deployment-audit/
├── deployment_<id>.log           # Human-readable deployment log
├── deployment_<id>.jsonl         # Machine-readable append-only audit trail
└── deployment_<id>_manifest.json # Deployment manifest with summary
```

### Audit Entry Format (JSONL)

```json
{
  "timestamp": "2024-03-08T22:40:15.123456Z",
  "event_type": "deployment_start",
  "component_id": "remove-embedded-secrets",
  "status": "in-progress",
  "details": {...},
  "error": null
}
```

## GitHub Issue Automation

The orchestrator automatically creates GitHub issues to track deployments:

### Master Tracking Issue
- **Title**: `🚀 Deployment: <deployment-id>`
- **Labels**: `deployment`, `automation`
- **Updated with**: Final status, audit trail links, component list

### Component Issues (Optional)
- **Title**: `[Status] Component: <name> (<id>)`
- **Labels**: `component`, `deployment`, `<status>`
- **Example**: `[✅] Component: Remove Embedded Secrets (remove-embedded-secrets)`

### Example Master Issue

```
## À la carte Deployment

**Deployment ID:** alacarte-20240308-224015-12345
**Trigger:** Manual
**Status:** ✅ Completed

### Components Deployed
- ✅ remove-embedded-secrets
- ✅ migrate-to-gsm
- ✅ setup-dynamic-credential-retrieval
- ✅ setup-credential-rotation

### Audit Trail
See .deployment-audit/deployment_alacarte-20240308-224015-12345.jsonl
```

## Architecture Guarantees

### Immutable
- All execution logged to append-only `.jsonl` files
- No modifications to audit trail after logging
- Enables compliance and forensic analysis

### Idempotent
- Safe to re-run deployments multiple times
- Each component validates current state before applying changes
- No duplicate side effects

### Ephemeral
- Temporary files auto-cleaned after deployment (> 30 days)
- No permanent data from temporary execution states
- Clean working directory after each run

### No-Ops
- Fully automated execution with zero manual steps
- Scheduled daily at 3 AM UTC
- Manual trigger via workflow dispatch
- Approval gate optional

### Secure
- Credentials injected from GSM/Vault/KMS, never stored
- OIDC tokens short-lived, auto-refreshed
- Workload Identity Federation eliminates service account keys
- No secrets in environment variables or logs

## Failure Handling

### Critical Component Failure
If a critical component fails (e.g., `remove-embedded-secrets`), deployment stops immediately:

```
❌ remove-embedded-secrets deployment failed: Cannot remove secrets safely
   Stopping deployment (critical component)
```

### Non-Critical Component Failure
Non-critical failures don't stop deployment. Marked as failed and escalated:

```
⚠️  setup-dynamic-credential-retrieval deployment failed: some warnings
   Continuing with next component (non-critical)
```

### Auto-Escalation
Critical failures create escalation issue:

```
🚨 CRITICAL: Deployment alacarte-20240308-224015-12345 failed
   See #1950 for details
```

## Validation & Testing

### Run in Dry-Run Mode First
Always validate deployment plan before execution:

```bash
python3 -m deployment.alacarte --deploy remove-embedded-secrets --dry-run
```

Output:
```
[DRY-RUN] git clone --depth 1 <repo>
[DRY-RUN] python3 scripts/security/scan_secrets.py --full-scan
...
✅ Dry-run completed successfully
```

### Validate Component Selection
Before deploying, verify all components and dependencies:

```python
from deployment.components import list_components, get_deployment_order

# List all components
for comp in list_components():
    print(f"{comp.component_id}: {comp.name}")

# Validate dependency order
components = ["remove-embedded-secrets", "migrate-to-gsm", "setup-credential-rotation"]
order = get_deployment_order(components)
print(f"Deployment order: {' → '.join(order)}")
```

### Monitor Live Deployment
Watch workflow progress:

```bash
# GitHub CLI
gh workflow run 01-alacarte-deployment.yml -f deployment_type=full-suite
gh run list --workflow 01-alacarte-deployment.yml --limit 1

# Or web UI
open https://github.com/kushin77/self-hosted-runner/actions
```

## Troubleshooting

### Deployment Fails on Credential Injection
**Issue**: `Required credential not found: GCP_PROJECT_ID`

**Solution**: Set environment variable or repository secret:
```bash
gh secret set GCP_PROJECT_ID --body "your-project-id"
```

### Circular Dependency Error
**Issue**: `Circular dependency detected in component deployment`

**Solution**: Components are incorrectly specified. Check:
```bash
python3 -m deployment.alacarte --list
```

And verify no component depends on a later one.

### Component Validation Fails
**Issue**: Component step fails but shouldn't fail deployment

**Solution**: Check if component is marked critical. Non-critical failures are logged but don't stop deployment.

### Audit Trail Not Written
**Issue**: `.deployment-audit/` is empty

**Solution**: Ensure write permissions to repository:
```bash
ls -la .deployment-audit/
git add .deployment-audit/
git commit -m "Audit logs from deployment"
```

## Production Checklist

- [ ] Review all available components: `python3 -m deployment.alacarte --list`
- [ ] Validate dependencies: `get_deployment_order(['...'])`
- [ ] Run dry-run: `--dry-run` mode
- [ ] Configure credentials: GSM/Vault/KMS setup
- [ ] Enable audit logging: `.deployment-audit/` accessible
- [ ] Review audit trail format
- [ ] Test GitHub issue integration
- [ ] Schedule daily at 3 AM UTC (configured)
- [ ] Set up monitoring for failed deployments
- [ ] Document deployment configuration
- [ ] Train team on deployment procedures

## Next Steps

1. **Review Components**: `python3 -m deployment.alacarte --list`
2. **Validate Selection**: Verify which components to deploy
3. **Configure Secrets**: Set up GSM/Vault/KMS credentials
4. **Test Dry-Run**: `--dry-run` before production
5. **Execute Deployment**: Choose deployment mode (full-suite, security, etc.)
6. **Monitor Progress**: Watch workflow and GitHub issues
7. **Verify Systems**: Confirm all components operational
8. **Review Audit Trail**: Check `.deployment-audit/` logs
9. **Close Tracking Issue**: When verified and ready
10. **Archive Success**: Document final state

## Summary

The **à la carte deployment orchestrator** enables enterprise-grade infrastructure-as-code with:

✅ Modular, selective component deployment
✅ Immutable audit trails for compliance
✅ Idempotent execution for safety
✅ Ephemeral resource cleanup
✅ Fully automated hands-off operation
✅ Multi-layer credential management (GSM/Vault/KMS)
✅ GitHub issue automation for tracking
✅ Zero manual intervention required

Deploy with confidence. **All changes logged. All operations safe. All systems monitored.**
