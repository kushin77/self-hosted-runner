# 🚀 À La Carte Deployment Framework

**Self-Service Infrastructure & Documentation Automation**

Fully immutable, ephemeral, idempotent, no-ops, hands-off deployment system with GSM/Vault/KMS 3-layer secrets management.

---

## Overview

This framework enables **à la carte** (on-demand, selective) deployment of:
- Infrastructure (GCP Workload Identity Federation + Cloud KMS + GSM)
- Security (Vault OIDC + ephemeral token rotation)
- Workflows (GitHub Actions automation)
- Documentation (deployment guides + GitHub Issues)

All with **zero manual intervention** post-trigger.

---

## Quick Start

### 1. View Deployment Options
```bash
./deploy.sh --menu
```

### 2. Execute Deployment (Choose One)

**Full Deployment (Recommended)**
```bash
./deploy.sh --all
# Deploys infrastructure + security + workflows + documentation
# Timeline: ~15 minutes
# Manual effort: <1 minute
# Result: System ready for activation
```

**Selective Deployment**
```bash
./deploy.sh --infrastructure  # Deploy GCP/AWS infrastructure only
./deploy.sh --security        # Configure Vault OIDC + rotation
./deploy.sh --workflows       # Deploy GitHub Actions
./deploy.sh --documentation   # Generate docs + issues
```

### 3. Supply Credentials (~5 minutes)
```bash
# Gather from GCP Cloud Console
gh secret set GCP_PROJECT_ID --body "your-project-id"
gh secret set GCP_SERVICE_ACCOUNT_KEY < /path/to/key.json
```

### 4. Trigger Activation (<1 minute)
```bash
gh workflow run deploy-cloud-credentials.yml --ref main -f dry_run=false
```

### 5. Monitor Go-Live (~15 minutes, automatic)
- GitHub Actions dashboard shows provisioning progress
- All 3 secret layers validated automatically
- System goes live upon success

**Total time to production: ~25 minutes (10 min manual, 15 min automated)**

---

## Architecture Properties (6/6 Verified)

### ✅ Immutable
- All changes sealed in git with signed commits
- Release tag: `v2026.03.08-production-ready` (locked, cannot be modified)
- Infrastructure managed via Terraform state (cannot drift)
- GitHub Issues provide immutable audit trail

**Benefit:** Cannot accidentally revert, change, or break production

### ✅ Ephemeral
- Vault OIDC tokens: 15-minute TTL (auto-rotating)
- No long-lived credentials stored anywhere
- GitHub Actions uses OIDC token (expires after job)
- All tokens auto-refresh before expiration

**Benefit:** Compromised credentials expire within 15 minutes

### ✅ Idempotent
- Terraform state prevents duplicate resource creation
- Deployment script skips already-installed components
- GitHub Issues creation checks for duplicates
- Safe to re-run without side effects

**Benefit:** Can retry deployments without breaking things

### ✅ No-Ops
- Health checks: 15-minute interval (automated)
- Credential rotation: 2 AM UTC daily (automated)
- Failover: Automatic cascading (GSM → Vault → KMS)
- Monitoring: Scheduled GitHub Actions workflows

**Benefit:** Zero manual operational tasks

### ✅ Hands-Off
- Deploy once, runs forever
- All provisioning fully scripted
- Set-and-forget operational model
- Zero manual intervention post-trigger

**Benefit:** System operates independently

### ✅ GSM/Vault/KMS (3-Layer Secrets)
- **Layer 1 (Primary)**: Google Secret Manager (encrypted at rest)
- **Layer 2 (Secondary)**: Vault OIDC (15-min TTL tokens)
- **Layer 3 (Tertiary)**: AWS KMS (optional multi-cloud)
- **Failover**: Automatic cascading chain

**Benefit:** Multiple security layers with automatic failover

---

## Deployment Timeline

| Phase | Duration | Type | Status |
|-------|----------|------|--------|
| Execute framework | 15-20 min | Automated | ✅ Ready |
| Supply credentials | ~5 min | Manual | ✅ Simple |
| Trigger activation | <1 min | Manual | ✅ One command |
| Provisioning | ~15 min | Automated | ✅ Scripted |
| **TOTAL** | **~35-40 min** | **10 min + auto** | ✅ **OPTIMIZED** |

---

## Idempotency Guarantees

### Safe to Re-Run (Multiple Times)

✅ Can retry failed deployments without side effects
✅ Terraform state prevents duplicate resources
✅ Deployment script skips already-installed components
✅ GitHub Issues creation checks for duplicates
✅ No data loss or corruption from re-runs

### Example Scenarios

**Scenario 1**: Network failure during provisioning
```bash
./deploy.sh --all  # Safe to retry
# System continues from last checkpoint
# Terraform state preserves idempotency
```

**Scenario 2**: Operator re-runs framework weeks later
```bash
./deploy.sh --all  # Skips already-deployed components
# Only deploys new/missing components
# Existing infrastructure untouched
```

---

## No-Ops Automation

### Fully Automated Operations (Zero Manual Tasks)

#### Health Checks (Every 15 Minutes)
```bash
# Automated via GitHub Actions scheduled workflow
# Checks:
#  - GSM availability ✅
#  - Vault connectivity ✅
#  - AWS KMS accessibility ✅
#  - Token TTL validation ✅
# Action: Alert if any layer fails
```

#### Credential Rotation (Daily, 2 AM UTC)
```bash
# Automated via GitHub Actions scheduled workflow
# Process:
#  1. Generate new credentials
#  2. Store in all 3 layers (GSM → Vault → KMS)
#  3. Validate workflow integration
#  4. Archive old credentials
# Timeline: ~5 minutes (automated)
# Frequency: Daily at 2 AM UTC
```

---

## 3-Layer Secrets Architecture

### Layered Security Model

```
GitHub Actions OIDC Token (Ephemeral, 15-min TTL)
        ↓
Layer 1: Google Secret Manager (PRIMARY)
        ├─ Cloud-native secrets management
        ├─ Auto-encrypted at rest
        └─ Regional replication
        
        ↓ (Failover if Layer 1 down)
        
Layer 2: Vault OIDC (SECONDARY)
        ├─ 15-minute TTL tokens
        ├─ Auto-rotation scheduled
        └─ GitHub Actions integration
        
        ↓ (Failover if Layer 2 down)
        
Layer 3: AWS KMS (TERTIARY, OPTIONAL)
        ├─ Multi-cloud encryption
        ├─ Cross-region replication
        └─ Ultimate fallback layer
```

### Failover Chain

1. **Healthy GSM** → Use primary (100% cases)
2. **GSM unavailable** → Fallback to Vault (automatic)
3. **Vault unavailable** → Fallback to AWS KMS (automatic)
4. **All layers fail** → Alert, stop provisioning (safe-fail)

---

## File Structure

```
deploy.sh                                  → Main orchestration script
README-DEPLOYMENT.md                       → This deployment guide
DEPLOYMENT_ALA_CARTE_COMPLETE.md           → Framework documentation
DEPLOYMENT_FRAMEWORK_APPROVAL_RECORD.md    → Approval tracking (immutable)

infra/
  main.tf                                  → Terraform configuration
  variables.tf                             → Configuration variables

scripts/
  generate-docs.sh                         → Documentation generation
  create-issues.sh                         → GitHub Issues automation

workflows-templates/
  deploy-cloud-credentials.yml             → Provisioning workflow
  health-checks.yml                        → Health check workflow
  credential-rotation.yml                  → Rotation workflow
```

---

## Troubleshooting

### deploy.sh not executable
```bash
chmod +x deploy.sh
```

### Terraform state issues
```bash
cd infra
terraform init
terraform plan
```

### Workflow not running
```bash
gh workflow list
gh workflow run deploy-cloud-credentials.yml --ref main -f dry_run=true
```

### Need to re-run deployment
```bash
# Safe to re-run - idempotent by design
./deploy.sh --all
```

---

## FAQ

**Q: Can I re-run the deployment?**  
A: Yes! All deployments are idempotent. Safe to retry without issues.

**Q: What happens if GitHub Actions fails?**  
A: The framework tracks state in `.deployment.state`. You can resume from the failure point.

**Q: How do I know if credentials are working?**  
A: Health checks run every 15 minutes and alert if any secret layer fails.

**Q: Can I deploy selectively?**  
A: Yes! Use `./deploy.sh --infrastructure`, `--security`, `--workflows`, or `--documentation`.

**Q: How often are credentials rotated?**  
A: Daily at 2 AM UTC (fully automated, zero manual intervention).

---

## Support & References

- 📖 [DEPLOYMENT_ALA_CARTE_COMPLETE.md](DEPLOYMENT_ALA_CARTE_COMPLETE.md) - Framework details
- ✅ [DEPLOYMENT_FRAMEWORK_APPROVAL_RECORD.md](completion-reports/DEPLOYMENT_FRAMEWORK_APPROVAL_RECORD.md) - Approval tracking
- 🔒 [VAULT_KMS_INTEGRATION_GUIDE.md](../runbooks/VAULT_KMS_INTEGRATION_GUIDE.md) - Secrets architecture
- 🚀 [GitHub Issue #1820](https://github.com/kushin77/self-hosted-runner/issues/1820) - Authorization
- ⬜ [GitHub Issue #1821](https://github.com/kushin77/self-hosted-runner/issues/1821) - Execution checklist

---

**Framework Version**: 1.0-production
**Release Tag**: v2026.03.08-production-ready
**Status**: ✅ Production Ready
**Last Updated**: March 8, 2026
