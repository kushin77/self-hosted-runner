# 📖 ENFORCEMENT & DOCUMENTATION INDEX
**Status:** ✅ **COMPLETE** | **Date:** March 14, 2026 | **Authority:** Production Standards

---

## 🎯 START HERE

**New to this repository?** Start with:

1. **[ENFORCEMENT_RULES.md](ENFORCEMENT_RULES.md)** - (10 min read)
   - The 5 core enforcement rules
   - What's blocked and what's required
   - Why each rule exists

2. **[DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md)** - (15 min read)
   - Step-by-step deployment workflow
   - Pre-deployment checklist
   - Rollback procedures

3. **[CODE_MANDATES.md](CODE_MANDATES.md)** - (20 min read)
   - How mandates are implemented in code
   - Copy-paste code patterns
   - Integration examples

4. **[ENFORCEMENT_TROUBLESHOOTING.md](ENFORCEMENT_TROUBLESHOOTING.md)** - (As needed)
   - Diagnose deployment failures
   - Fix common issues
   - Escalation procedures

---

## 📋 ENFORCEMENT RULES SUMMARY

| Rule | Mandate | Check | Status |
|------|---------|-------|--------|
| **#1** | No manual infrastructure changes | `bash scripts/enforce/verify-no-manual-changes.sh` | ✅ Enforced |
| **#2** | No hardcoded secrets anywhere | Pre-commit hook (automatic) | ✅ Enforced |
| **#3** | Immutable audit trail | `bash scripts/enforce/verify-audit-trail-integrity.sh` | ✅ Enforced |
| **#4** | Automated health gating | `bash scripts/ssh_service_accounts/preflight_health_gate.sh` | ✅ Enforced |
| **#5** | Zero-trust credential access | `bash scripts/ssh_service_accounts/fetch-credential.sh` | ✅ Enforced |
| **#6** | Fresh build (on-prem only) | `TARGET_HOST=192.168.168.42 bash deploy-worker-node.sh` | ✅ **NEW** |

---

## 🚀 QUICK COMMANDS

```bash
# Check prerequisites before deployment
bash scripts/enforce/check-prerequisites.sh

# Verify all enforcement rules
bash scripts/enforce/diagnose.sh

# Run pre-deployment validation (DO THIS EVERY TIME)
bash scripts/enforce/verify-no-manual-changes.sh && \
  bash scripts/ssh_service_accounts/preflight_health_gate.sh && \
  bash scripts/enforce/verify-audit-trail-integrity.sh

# Deploy with fresh build (MANDATE: complete rebuild, on-prem only)
# Step 1: Merge to main
git push origin main  # Auto-deployment triggered with fresh build

# Step 2: Manual deployment (if needed)
# PHASE 1: Validate mandate (no cloud, on-prem verified)
# PHASE 2: Clean slate (remove previous state)
# PHASE 3: Fresh provisioning (complete rebuild)
# PHASE 4: Fresh credentials (Ed25519 SSH keys)
TARGET_HOST=192.168.168.42 bash deploy-worker-node.sh

# Check deployment status
git log --oneline -5
bash scripts/ssh_service_accounts/health_check.sh report

# Verify fresh build deployment
ssh automation@192.168.168.42 "ls -l /opt/automation/deployment/ | head"

# Troubleshoot issues
bash scripts/enforce/diagnose.sh
```

---

## ⚡ CRITICAL MANDATE: Fresh Build Deployment (Rule #6)

> **EVERY deployment must:**
> - ✅ Be a **FRESH BUILD** (complete rebuild from scratch)
> - ✅ Target **ON-PREM ONLY** (192.168.168.42 or 192.168.168.39)
> - ✅ Have **NO CLOUD** credentials (GCP, AWS, Azure blocked)
> - ✅ Generate **FRESH CREDENTIALS** (new Ed25519 SSH keys)
> - ✅ Remove **PREVIOUS STATE** (clean slate approach)

### What Fresh Build Means
```
❌ NOT ALLOWED: Keep old state, incremental updates, cloud targets
✅ REQUIRED: Complete clean rebuild, on-prem only, fresh credentials

DEPLOYMENT PHASES:
1. Mandate Validation: Detect & block cloud, verify on-prem target
2. Clean Slate: Remove all previous deployment state
3. Fresh Provisioning: Clone & deploy entire stack from scratch
4. Fresh Credentials: Generate new Ed25519 SSH key pairs
```

---

## 📚 DETAILED DOCUMENTATION

### Infrastructure & Operations
- **[OPERATIONS_MANDATE.md](OPERATIONS_MANDATE.md)** - Operational rules for running systems
- **[OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md)** - Quick reference commands
- **[SSH_KEYS_ONLY_GUIDE.md](SSH_KEYS_ONLY_GUIDE.md)** - SSH authentication setup
- **[GOVERNANCE_RULES.md](GOVERNANCE_RULES.md)** - Authority and sign-off procedures

### Development & Deployment  
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Development workflow and standards
- **[DEPLOY_RUNBOOK.md](DEPLOY_RUNBOOK.md)** - Deployment procedures
- **[README.md](README.md)** - Project overview and status

### Compliance & Policy
- **[FAANG_CICD_STANDARDS.md](FAANG_CICD_STANDARDS.md)** - Enterprise-grade standards
- **[POLICIES/NO_GITHUB_ACTIONS.md](POLICIES/NO_GITHUB_ACTIONS.md)** - GitHub Actions prohibition
- **[.github/POLICY.md](.github/POLICY.md)** - Repository policy enforcement

---

## ✅ COMPLIANCE MATRIX

### Rule #1: No Manual Changes
| Check | Pass? | Command |
|-------|-------|---------|
| No uncommitted infra changes | ✅ | `bash scripts/enforce/verify-no-manual-changes.sh` |
| All changes via git | ✅ | `git log --oneline` |
| Audit trail in commits | ✅ | `git log --all --grep="deployment"` |

### Rule #2: No Hardcoded Secrets
| Check | Pass? | Command |
|-------|-------|---------|
| Pre-commit hook enabled | ✅ | `pre-commit run --all-files` |
| No AWS keys in code | ✅ | (Automatic on commit) |
| No GitHub tokens | ✅ | (Automatic on commit) |
| No private keys | ✅ | (Automatic on commit) |

### Rule #3: Immutable Audit Trail
| Check | Pass? | Command |
|-------|-------|---------|
| Audit log exists | ✅ | `ls -la logs/credential-audit.jsonl` |
| Hash-chain verified | ✅ | `bash scripts/enforce/verify-audit-trail-integrity.sh` |
| No tampering detected | ✅ | (Automatic verification) |
| 12-month retention | ✅ | (Enforced by automation) |

### Rule #4: Health Gating
| Check | Pass? | Command |
|-------|-------|---------|
| All commands available | ✅ | `bash scripts/enforce/check-prerequisites.sh` |
| All directories exist | ✅ | (Automatic verification) |
| SSH key permissions correct | ✅ | `ls -la secrets/ssh/*/id_ed25519` |
| Systemd services enabled | ✅ | `systemctl list-units --type=service` |
| Systemd timers active | ✅ | `systemctl list-timers` |
| Disk space sufficient | ✅ | `df -h` |
| Targets reachable | ✅ | (SSH connectivity test) |

### Rule #5: Zero-Trust Access
| Check | Pass? | Command |
|-------|-------|---------|
| Vault accessible | ✅ | `vault status` |
| GSM secrets available | ✅ | `gcloud secrets list --project=nexusshield-prod` |
| KMS encryption ready | ✅ | `gcloud kms keys list` |
| Credentials fetched via API | ✅ | `source scripts/ssh_service_accounts/fetch-credential.sh` |

---

## 🔍 ENFORCEMENT SCRIPTS

All enforcement scripts located in `scripts/enforce/`:

| Script | Purpose | Usage |
|--------|---------|-------|
| `verify-no-manual-changes.sh` | Rule #1 enforcement | `bash scripts/enforce/verify-no-manual-changes.sh` |
| `verify-audit-trail-integrity.sh` | Rule #3 enforcement | `bash scripts/enforce/verify-audit-trail-integrity.sh` |
| `check-prerequisites.sh` | Prerequisites check | `bash scripts/enforce/check-prerequisites.sh` |
| `diagnose.sh` | Full system diagnosis | `bash scripts/enforce/diagnose.sh` |
| `find-secrets.sh` | Locate hardcoded secrets | `bash scripts/enforce/find-secrets.sh` |
| `remove-secrets.sh` | Bulk secret removal | `bash scripts/enforce/remove-secrets.sh` |
| `cleanup-old-logs.sh` | Storage cleanup | `bash scripts/enforce/cleanup-old-logs.sh` |
| `create-incident.sh` | Create GitHub incident | `bash scripts/enforce/create-incident.sh` |

---

## 🚨 WHAT BLOCKS DEPLOYMENT?

```
Deployment is automatically blocked (with clear error) if:
  ❌ Pre-commit hook detects hardcoded secrets
  ❌ Manual infra changes detected (Rule #1)
  ❌ Health gate fails (Rule #4)
  ❌ Audit trail verification fails (Rule #3)
  ❌ Credentials inaccessible (Rule #5)
  ❌ GitHub branch protection not met
  ❌ Cloud Build job failure
```

**All blocks have clear fix instructions included in the error message.**

---

## 📊 PRODUCTION STATUS

### Deployment Infrastructure
- ✅ 32+ service accounts deployed
- ✅ 5 systemd services running
- ✅ 2 automation timers active
- ✅ 38+ Ed25519 SSH keys secured
- ✅ 5 compliance standards verified

### Enforcement Status
- ✅ Rule #1: No manual changes (git tracked, audit logged)
- ✅ Rule #2: No secrets (pre-commit blocking)
- ✅ Rule #3: Audit trail (hash-chain verified)
- ✅ Rule #4: Health gating (11-category validation)
- ✅ Rule #5: Zero-trust access (multi-layer fallback)

### Automation Status
- ✅ Pre-commit hooks: Passing
- ✅ Cloud Build: Configured
- ✅ Auto-deployment: Active
- ✅ Health checks: Running hourly
- ✅ Credential rotation: 90-day cycle

---

## 🆘 NEED HELP?

| Question | Resource |
|----------|----------|
| "How do I deploy?" | [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md) |
| "What rules apply?" | [ENFORCEMENT_RULES.md](ENFORCEMENT_RULES.md) |
| "How are rules enforced in code?" | [CODE_MANDATES.md](CODE_MANDATES.md) |
| "Something's broken" | [ENFORCEMENT_TROUBLESHOOTING.md](ENFORCEMENT_TROUBLESHOOTING.md) |
| "What's the development workflow?" | [CONTRIBUTING.md](CONTRIBUTING.md) |
| "Day-to-day operations?" | [OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md) |

### Slack Channels
- **#engineering-deployments** - Questions about deployment
- **#engineering-oncall** - Production emergencies
- **#engineering-security** - Security and compliance questions

---

## 📅 LAST UPDATE

| Document | Last Updated | Version |
|----------|--------------|---------|
| ENFORCEMENT_RULES.md | 2026-03-14 | 1.0 |
| DEPLOYMENT_INSTRUCTIONS.md | 2026-03-14 | 1.0 |
| CODE_MANDATES.md | 2026-03-14 | 1.0 |
| ENFORCEMENT_TROUBLESHOOTING.md | 2026-03-14 | 1.0 |

**All documentation current and applicable. Last verified: 2026-03-14**

---

## 🎓 LEARNING PATH

**For New Developers:**
1. Read: [README.md](README.md) - What is this project?
2. Read: [ENFORCEMENT_RULES.md](ENFORCEMENT_RULES.md) - What are the rules?
3. Read: [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md) - How do I work?
4. Read: [CONTRIBUTING.md](CONTRIBUTING.md) - How do I contribute?
5. Do: First deployment following exact checklist
6. Reference: [CODE_MANDATES.md](CODE_MANDATES.md) - When writing new code

**For Operations/DevOps:**
1. Read: [ENFORCEMENT_RULES.md](ENFORCEMENT_RULES.md) - What's required?
2. Read: [OPERATIONS_MANDATE.md](OPERATIONS_MANDATE.md) - What are my responsibilities?
3. Read: [OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md) - Day-to-day commands
4. Reference: [ENFORCEMENT_TROUBLESHOOTING.md](ENFORCEMENT_TROUBLESHOOTING.md) - When issues occur

**For Security/Compliance:**
1. Read: [GOVERNANCE_RULES.md](GOVERNANCE_RULES.md) - How is authority structured?
2. Read: [CODE_MANDATES.md](CODE_MANDATES.md) - How are security controls implemented?
3. Read: [FAANG_CICD_STANDARDS.md](FAANG_CICD_STANDARDS.md) - Enterprise standards
4. Review: [logs/credential-audit.jsonl](logs/credential-audit.jsonl) - Audit trail

---

## ✨ SUMMARY

This repository implements **5 enforcement rules** through:
- ✅ Automated pre-commit hooks (block bad commits)
- ✅ Automated Cloud Build validation (block bad deployments)
- ✅ Automated health gating (block unhealthy operations)
- ✅ Immutable audit trail (track everything)
- ✅ Clear documentation (help everyone succeed)

**Result:** Production-grade infrastructure with zero manual intervention required.

