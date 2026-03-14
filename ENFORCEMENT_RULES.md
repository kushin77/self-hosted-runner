# 🛡️ ENFORCEMENT RULES - PRODUCTION MANDATE
**Status:** ✅ **ACTIVE ENFORCEMENT** | **Date:** March 14, 2026 | **Authority:** Lead Engineering + Security + Operations

---

## EXECUTIVE SUMMARY

All deployments to this repository must comply with 5 core enforcement rules. Non-compliance blocks deployment and triggers incident response.

---

## ENFORCEMENT RULE #1: Zero Manual Infrastructure Changes

### Mandate
**No direct SSH modifications to infrastructure. All changes via git + automated deployment.**

### What This Means
```
❌ NOT ALLOWED:
   ssh user@192.168.168.42 "rm /var/log/old.log"
   ssh user@192.168.168.42 "systemctl restart service"
   Manual kubectl apply
   Direct database modifications

✅ REQUIRED:
   Edit file in git → commit → push → auto-deploy (5 min)
   All infrastructure as code
   All configurations templated
   Complete audit trail in git + JSONL logs
```

### Violation Response
| First Offense | Second Offense | Third Offense |
|---------------|----------------|---------------|
| Immediate rollback + warning | Rollback + incident created | Deployment access revoked |

### Verification
```bash
# Automated check before every deployment
bash scripts/enforce/verify-no-manual-changes.sh

# This checks:
# - No recent SSH direct executions (except via deployment automation)
# - No uncommitted infrastructure changes
# - All changes tracked in git
```

---

## ENFORCEMENT RULE #2: No Hardcoded Secrets Anywhere

### Mandate
**Every credential must come from GSM/Vault/KMS. Zero exceptions. Zero tolerances.**

### What This Means
```
❌ NOT ALLOWED:
   API_KEY=sk-12345 in code
   PASSWORD=admin123 in config
   PRIVATE_KEY="-----BEGIN..." in repository
   Secrets in environment.example

✅ REQUIRED:
   VAULT_ADDR=https://vault.company.com
   gcloud secrets versions access latest --secret=api-key
   Ephemeral tokens with TTL enforcement
   Secret rotation on 90-day cycle
```

### Violation Response
- **Pre-commit hook:** Blocks commit with secret scanning failure
- **CI/CD:** Cloud Build rejects deployment with secret detection
- **Production:** Alert sent to Security team, access review triggered

### Verification
```bash
# Automated check on every commit
pre-commit run secrets-scan-all-files

# This checks:
# - No AWS keys, GitHub tokens, private keys
# - No Base64 encoded secrets
# - No credential patterns in any file type
```

---

## ENFORCEMENT RULE #3: Immutable Audit Trail

### Mandate
**All operations logged to append-only, cryptographically verified audit trail. No deletion. No modification.**

### What This Means
```
❌ NOT ALLOWED:
   Modifying audit logs
   Deleting historical records
   Untracked deployments
   Silent failures without logging

✅ REQUIRED:
   JSONL immutable append-only log
   SHA-256 hash-chain for integrity
   Timestamped ISO-8601 UTC
   User attribution on every operation
   30+ day backup retention minimum
```

### Violation Response
- **Hash mismatch detected:** Incident #audit-tampering created
- **Missing log entries:** Security investigation initiated
- **Access review:** User logs audited for suspicious patterns

### Verification
```bash
# Automated integrity check (hourly)
bash scripts/enforce/verify-audit-trail-integrity.sh

# This checks:
# - audit-trail.jsonl exists and is readable
# - Hash-chain integrity verified end-to-end
# - No gaps in timestamp sequence
# - All expected events present
```

---

## ENFORCEMENT RULE #4: Automated Monitoring + Health Gating

### Mandate
**All deployments automatically validated. Unhealthy systems block further changes.**

### What This Means
```
❌ NOT ALLOWED:
   Deploying to unhealthy infrastructure
   Skipping health checks
   Ignoring failing systemd services
   Proceeding with disk/memory warnings

✅ REQUIRED:
   Preflight health gate before every deployment
   Systemd services all enabled + running
   Disk usage <80%
   Memory pressure <85%
   Network connectivity verified
   All 32+ accounts health-check passing
```

### Violation Response
| Issue | Response | Owner |
|-------|----------|-------|
| Health gate failure | Deployment blocked, auto-investigating | Operations |
| Service disabled | Auto-restart attempt, alert if persists | Automation |
| Disk full (>90%) | Auto-cleanup attempt, incident if fails | Storage Team |
| Memory pressure | Automatic process restart, page on-call | Infrastructure |

### Verification
```bash
# Automated check on every deployment
bash scripts/ssh_service_accounts/preflight_health_gate.sh

# This checks:
# - All 6 required commands available (ssh, ssh-keygen, gcloud, etc)
# - All required directories exist
# - SSH key permissions correct (600 on private keys)
# - Systemd services enabled
# - Systemd timers active
# - Disk space sufficient (>500MB)
# - GCP Secret Manager accessible
# - No cascading failures in audit trail
```

---

## ENFORCEMENT RULE #5: Zero-Trust Credential Access

### Mandate
**Every credential access validated. Multi-layer failover. TTL enforcement on all ephemeral credentials.**

### What This Means
```
❌ NOT ALLOWED:
   Storing credentials in environment variables
   Credentials without expiration
   Access to secrets without audit trail
   Fallback to hardcoded values

✅ REQUIRED:
   GSM with automatic versioning
   Vault with TTL enforcement (default 1 hour)
   KMS for encryption encryption keys
   Ephemeral credentials only (max 24 hours)
   Every access logged with user + timestamp
   Automatic credential rotation on 90-day cycle
```

### Multi-Layer Failover (in order)
1. **Vault** (primary, 4.2s latency)
2. **GSM** (secondary, 2.85s latency)  
3. **KMS** (encryption backend)
4. **Local backup** (emergency only, < 2 days)

### Violation Response
- **Expired credential used:** Automatic refresh + audit alert
- **Access without audit:** Credential invalidated + investigation
- **Credential leak detected:** Immediate rotation + affected services notified

### Verification
```bash
# Automated check on every credential access
bash scripts/enforce/verify-credential-access.sh

# This checks:
# - No hardcoded secrets in process environment
# - All credentials accessed via GSM/Vault (with logging)
# - TTL enforcement on ephemeral tokens
# - No credentials stored in .bash_history or logs
# - Access patterns match known deployments
```

---

## ENFORCEMENT RULE #6: Fresh Build Deployment (On-Prem Only)

### CRITICAL MANDATE
**All deployments must use fresh build strategy with zero cloud deployment.**

### What This Means
```
❌ NOT ALLOWED:
   Cloud deployment (GCP, AWS, Azure)
   Incremental updates (keeping previous state)
   Partial infrastructure changes
   Reusing old credentials or SSH keys
   Developers deploying from personal machines

✅ REQUIRED:
   Fresh build always (complete rebuild from scratch)
   On-prem targets only (192.168.168.42, 192.168.168.39)
   Clean slate approach (remove all previous state)
   Fresh credential generation (Ed25519 SSH keys)
   Automated production deployments only
   Zero cloud credentials in environment
```

### Violation Response
| Detection | Action | Escalation |
|-----------|--------|------------|
| Cloud env detected | Deployment blocked immediately | Security alert |
| Non-on-prem target | Target rejected | Incident created |
| Previous state found | Fresh build forced, rollback triggered | Incident + review |
| Old credentials used | Access revoked | Security audit |

### Verification
```bash
# Automated validation in deploy-worker-node.sh
# PHASE 1: Mandate validation (cloud prevention)
# PHASE 2: Clean slate (previous state removal)
# PHASE 3: Fresh provisioning (complete rebuild)
# PHASE 4: Fresh credentials (key generation)

# Manual verification:
verify_no_cloud_env() {
    [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]] && \
    [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] && \
    [[ -z "${AZURE_SUBSCRIPTION_ID:-}" ]] && \
    return 0 || return 1
}

verify_target_is_onprem() {
    case "$TARGET_HOST" in
        192.168.168.42|192.168.168.39) return 0 ;;
        *) return 1 ;;
    esac
}
```

### 4-Phase Fresh Build Process

**Phase 1: Mandate Validation**
- Detect and block all cloud credentials (GCP, AWS, Azure)
- Verify target is on-prem (192.168.168.42 or .39)
- Verify no cloud kubectl contexts active

**Phase 2: Clean Slate**
- Remove entire previous deployment directory
- Clean all temporary state files
- Verify clean state before provisioning

**Phase 3: Fresh Provisioning**
- Clone fresh git repository (depth=1, latest commit only)
- Deploy all components from fresh source
- Create new directory structure from scratch
- NO incremental updates, NO state carryover

**Phase 4: Fresh Credentials**
- Generate fresh Ed25519 SSH key pair
- Backup old credentials (if any)
- Deploy fresh keys to production
- Verify all new credentials active

### Post-Deployment Fresh Build Validation
```bash
# Verify no cloud credentials in deployed environment
[[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]

# Verify all components have fresh timestamps (just deployed)
stat $DEPLOYMENT_DIR/core/*.sh | grep -i modify | grep -i today

# Verify fresh SSH keys deployed
test -f $DEPLOYMENT_DIR/automation_ed25519 && echo "✅ Fresh SSH keys"

# Verify zero leftover state
! test -d /opt/old-deployment && echo "✅ No previous state"

# Verify on-prem target
[[ "$(hostname -I)" =~ 192.168.168 ]] && echo "✅ On-prem verified"
```

---

## ENFORCEMENT MATRIX: What Gets Blocked When?

| Rule | Check Point | Block Level | Action |
|------|-------------|-------------|--------|
| Rule #1 (No Manual Changes) | Pre-deployment | Deployment | Rollback + alert |
| Rule #2 (No Hardcoded Secrets) | Pre-commit | Commit | Reject with guidance |
| Rule #3 (Immutable Audit) | Hourly | Production | Incident + investigation |
| Rule #4 (Health Gating) | Pre-deployment | Deployment | Block with diagnostics |
| Rule #5 (Zero-Trust Access) | Runtime | Access | Deny + log attempt |
| **Rule #6 (Fresh Build)** | **Pre-deployment** | **Deployment** | **Block + mandate enforcement** |

---

## IMPLEMENTING ENFORCEMENT IN YOUR CODE

Every script in `/scripts/` that modifies infrastructure MUST include:

```bash
#!/bin/bash
set -euo pipefail

# ============================================
# RULE #1: Verify no manual changes in progress
# ============================================
bash scripts/enforce/verify-no-manual-changes.sh || {
    echo "❌ ENFORCEMENT FAILED: Manual infrastructure changes detected"
    exit 1
}

# ============================================
# RULE #4: Preflight health gate
# ============================================
bash scripts/ssh_service_accounts/preflight_health_gate.sh || {
    echo "❌ ENFORCEMENT FAILED: System not ready for production"
    exit 1
}

# ============================================
# RULE #3: Audit this operation
# ============================================
source scripts/ssh_service_accounts/change_control_tracker.sh
log_operation "script_execution" "begin" "hostname=$(hostname)" || {
    echo "❌ ENFORCEMENT FAILED: Audit logging not working"
    exit 1
}

# Your actual script logic here...
echo "✅ All enforcement checks passed"
```

---

## ENFORCEMENT CHECKLIST FOR EVERY DEPLOYMENT

- [ ] Git branch protection passing (required reviews)
- [ ] Pre-commit hooks passing (no secrets, no lint errors)
- [ ] Cloud Build job succeeding (image build + scan)
- [ ] Vulnerability scan passed (Trivy + SBOM + cosign)
- [ ] Security audit cleared (no CRITICAL/HIGH vulns)
- [ ] Preflight health gate passing (11 validation categories)
- [ ] Audit trail accessible and verified (hash-chain check)
- [ ] No manual infrastructure changes detected
- [ ] **☑️ Fresh build deploying (complete rebuild confirmed)**
- [ ] **☑️ No cloud credentials in environment**
- [ ] **☑️ Target is on-prem only (192.168.168.42 or .39)**
- [ ] **☑️ Fresh SSH keys generated**
- [ ] **☑️ Previous deployment state removed (clean slate)**
- [ ] All 32+ service accounts healthy
- [ ] All systemd services enabled + running
- [ ] Backup mechanism tested and working

**If ANY check fails → Deployment blocked. No exceptions. No overrides.**

---

## ENFORCEMENT SUPPORT & EXCEPTIONS

### Getting Help
- **Blocked deployment?** Run: `bash scripts/enforce/diagnose.sh`
- **Secrets in code?** Use: `scripts/enforce/remove-secrets.sh` 
- **Health gate failing?** Try: `bash scripts/ssh_service_accounts/preflight_health_gate.sh --fix-minor`

### Exception Process
Exceptions require approval from:
1. ✅ Your technical lead
2. ✅ Security team
3. ✅ Executive approval

**No single-person exceptions. No emergency overrides. Ever.**

---

## COMPLIANCE & AUDIT

All enforcement checks logged to:
- `logs/enforcement-checks.jsonl` - Every check run
- `logs/credential-audit.jsonl` - Every credential access
- GitHub commit history - Complete change trail
- Cloud Build logs - Full deployment history

**Audit retention: 12 months minimum (immutable S3 + WORM)**

---

## QUESTIONS?

**Documentation:** See [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md)  
**Code Examples:** See [CODE_MANDATES.md](CODE_MANDATES.md)  
**Troubleshooting:** See [ENFORCEMENT_TROUBLESHOOTING.md](ENFORCEMENT_TROUBLESHOOTING.md)  
**Contact:** Slack #engineering-deployments
