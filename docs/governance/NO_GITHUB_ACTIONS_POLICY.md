# NO GITHUB ACTIONS POLICY - ENFORCEMENT STANDARD

**Effective Date:** 2026-03-10  
**Status:** ✅ **MANDATORY ENFORCEMENT**  
**Authority:** Self-Hosted Runner Direct Deployment Framework  
**Severity:** CRITICAL - No Exceptions

---

## 1. CORE POLICY

### ❌ **STRICTLY PROHIBITED:**
- NO GitHub Actions workflows (any file in `.github/workflows/`)
- NO GitHub Actions triggering deployments
- NO GitHub Actions automation
- NO GitHub Actions pull request checks
- NO GitHub Actions scheduled workflows
- NO GitHub Actions release processes
- NO GitHub pull request releases
- NO GitHub Actions intermediaries

### ✅ **ONLY APPROVED METHOD:**
**Direct Deployment via SSH + Shell Scripts**
```bash
./scripts/deployment/deploy-to-production.sh
# OR
ssh -i /path/to/key user@host './scripts/deployment/deploy.sh'
```

---

## 2. CREDENTIAL MANAGEMENT (MULTI-LAYER: GSM → VAULT → KMS)

### Forbidden Credential Storage:
❌ GitHub Secrets  
❌ GitHub Environment Variables  
❌ Repository files  
❌ Environment files (.env in git)  
❌ Docker environment variables  
❌ Any plaintext storage  

### Required Credential Sources:
✅ **Google Secret Manager (GSM)** - Primary  
✅ **HashiCorp Vault** - Fallback  
✅ **AWS KMS/Secrets Manager** - Tertiary  

### Credential Retrieval Flow:
```
Deployment Script
  ↓
1. Try GSM: gcloud secrets versions access latest --secret=<name>
  ↓ (if fails)
2. Try Vault: vault kv get secret/<path>
  ↓ (if fails)
3. Try KMS: aws secretsmanager get-secret-value --secret-id=<name>
  ↓ (if all fail)
FATAL_ERROR: Exit code 1 (no plaintext fallback)
```

### Example Credential Injection:
```bash
#!/bin/bash
# Fetch from GSM (primary)
DB_PASSWORD=$(gcloud secrets versions access latest --secret="prod-db-password") || \
# Fetch from Vault (fallback)
DB_PASSWORD=$(vault kv get -field=password secret/db-creds) || \
# Fetch from AWS (tertiary)
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id=prod-db --query SecretString --output text)

export DB_PASSWORD
./deploy.sh
```

---

## 3. DIRECT DEPLOYMENT ARCHITECTURE

### No GitHub Actions = No Dependency On:
- ❌ GitHub workflow scheduling
- ❌ GitHub branch protection hooks
- ❌ GitHub pull request automation
- ❌ GitHub CI status checks
- ❌ GitHub Actions environment secrets
- ❌ GitHub Actions encryption

### Allowed Automation Alternatives:
✅ Cron jobs (direct SSH execution)  
✅ External CI platforms (Jenkins, GitLab CI, etc.)  
✅ Manual script execution  
✅ Terraform automation runner  
✅ Ansible playbooks  
✅ Any external tool (NOT GitHub Actions)  

### Deployment Flow (NO GitHub Actions):
```
Human/External Automation
  ↓
Initiates: ./scripts/deployment/deploy-to-production.sh
  ↓
Script Execution:
  1. Validate environment
  2. Fetch credentials (GSM → Vault → KMS)
  3. Build/test locally
  4. Deploy to target (SSH remote execution)
  5. Health check (curl, API test)
  6. Record audit trail (immutable)
  ↓
Exit: Success (0) or Failure (1)
  ↓
Optional: External notification (Slack/PagerDuty, NOT GitHub)
```

---

## 4. IMMUTABLE AUDIT TRAIL

Every deployment MUST record:
```json
{
  "timestamp": "2026-03-10T10:00:00Z",
  "operator": "automation-user",
  "environment": "production",
  "version_sha": "abc123def456...",
  "status": "success",
  "duration_seconds": 120,
  "credentials_source": "GSM",
  "health_check": "passed",
  "audit_immutable": true
}
```

**Location:** `logs/deployments/YYYY-MM-DD-environment.jsonl` (append-only)

**Rules:**
- ✅ All deployments logged
- ✅ No deletion of audit entries
- ✅ No modification of existing entries
- ✅ Timestamps UTC ISO 8601 format
- ✅ Archive maintained forever

---

## 5. FULLY AUTOMATED HANDS-OFF REQUIREMENTS

All deployments MUST be:

1. **Immutable** - Changes recorded forever (append-only)
2. **Ephemeral** - Resources created/destroyed per deployment
3. **Idempotent** - Safe to execute multiple times (same result)
4. **No-Ops** - Fully automated (zero manual steps)
5. **Hands-Off** - No human intervention during execution
6. **Self-Healing** - Automatic rollback on failure

### Example Idempotent Deployment Script:
```bash
#!/bin/bash
set -euo pipefail

# Immutable: Append-only audit trail
LOG_FILE="logs/deployments/$(date +%Y-%m-%d-%H%M%S).jsonl"
log_event() {
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"$1\"}" >> "$LOG_FILE"
}

# Ephemeral: Create temp directory
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR; log_event 'cleanup_complete'" EXIT

# Idempotent: Check current state
if docker ps -q --filter "name=^app$" | grep -q .; then
  log_event "stop_existing_container"
  docker stop app || true
fi

# Fetch credentials from GSM (primary)
log_event "fetch_credentials_gsm"
CREDS=$(gcloud secrets versions access latest --secret="app-creds" 2>/dev/null) || \
CREDS=$(vault kv get -field=data secret/app 2>/dev/null) || \
CREDS=$(aws secretsmanager get-secret-value --secret-id=app --query SecretString --output text 2>/dev/null) || \
{ log_event "credential_fetch_failed"; exit 1; }

echo "$CREDS" > "$TMPDIR/creds.json"

# Deploy
log_event "deployment_starting"
docker run -d \
  --name=app \
  --restart=unless-stopped \
  -e CREDENTIALS_FILE="$TMPDIR/creds.json" \
  app:latest

# Health check loop (10 attempts, 5 second intervals)
log_event "health_check_starting"
for i in {1..10}; do
  sleep 5
  if curl -sf http://localhost:8080/health > /dev/null; then
    log_event "health_check_passed"
    echo "✅ Deployment successful"
    exit 0
  fi
  log_event "health_check_attempt_$i"
done

# Failure: Rollback
log_event "health_check_failed_rolling_back"
docker stop app
exit 1
```

---

## 6. KEY ROTATION & SECRET MANAGEMENT

### Rotation Schedule:
- **Frequency:** Every 30 days (automated)
- **Method:** `scripts/provisioning/rotate-secrets.sh`
- **Verification:** Test both old + new keys simultaneously
- **Rollback Window:** 24 hours to revert if needed

### Credential Scopes:
```
GSM Service Account:
  ├─ Role: Secret Accessor (read-only)
  ├─ Scope: Single project
  ├─ Expiration: 90 days (auto-renewal)
  └─ Audit: All access logged

Vault Token:
  ├─ TTL: 24 hours
  ├─ Renewable: Yes (auto-renewed per deployment)
  ├─ Policies: deployment-only (minimal scope)
  └─ Audit: Revoked after deployment

AWS IAM:
  ├─ User: ci-deployment-user (headless)
  ├─ MFA: Not required (headless execution)
  ├─ Session: 1 hour max duration
  ├─ Permissions: Minimal (only what needed)
  └─ Audit: CloudTrail logs all API calls
```

### Credential Exposure Response (SLA 15 minutes):
1. **Immediate (5 min):** Revoke/rotate in ALL 3 systems (GSM/Vault/KMS)
2. **Verify (5 min):** Test new credentials in isolation
3. **Deploy (5 min):** Re-execute deployment with new creds
4. **Document (30 min):** Record incident in `docs/archive/security/incidents/`
5. **Review (24 hours):** Post-incident analysis & remediation

---

## 7. NO GITHUB RELEASES

### Forbidden:
- ❌ GitHub Releases (automatic)
- ❌ GitHub Release automation
- ❌ GitHub tag-based releases
- ❌ Changelog generation via CI

### Approved Alternative:
- ✅ Manual release notes: `docs/archive/releases/v1.0.0.md`
- ✅ Git tag locally: `git tag v1.0.0 && git push origin v1.0.0`
- ✅ Release documentation: Manual authoring  
- ✅ Release testing: Manual verification + audit log

---

## 8. REPOSITORY CHECKS (ONGOING ENFORCEMENT)

### Verify No GitHub Actions:
```bash
# Should return 0
find .github/workflows -name "*.yml" 2>/dev/null | wc -l

# Should return no results
grep -r "name: " .github/workflows 2>/dev/null

# Should return 0
grep -r "on:" .github/workflows 2>/dev/null
```

### Verify All Credentials Secured:
```bash
# Should return 0 (no plaintext passwords)
grep -r "password" . --include="*.sh" 2>/dev/null | grep -v "GSM\|Vault\|KMS" | wc -l

# Should return 0 (no GitHub secrets)
grep -r "secrets\." . --include="*.yml" 2>/dev/null | wc -l
```

---

## 9. MIGRATION FROM GITHUB ACTIONS (If Currently Using)

### Step 1: Inventory All Workflows
```bash
find .github/workflows -name "*.yml" > /tmp/actions-to-migrate.txt
```

### Step 2: Convert Each Workflow to Shell Script
```bash
# OLD (GitHub Actions - FORBIDDEN)
- name: Deploy
  run: npm run deploy
  env:
    DB_PASSWORD: ${{ secrets.DB_PASSWORD }}

# NEW (Direct Script - APPROVED)
#!/bin/bash
export DB_PASSWORD=$(gcloud secrets versions access latest --secret="db-password")
npm run deploy
```

### Step 3: Secure All Credentials
Move from GitHub Secrets → GSM/Vault/KMS

### Step 4: Test Direct Execution
```bash
./scripts/deployment/deploy-to-production.sh
# Verify success (exit 0)
```

### Step 5: Clean Up GitHub Actions
```bash
rm -rf .github/workflows
rm -rf .github/actions
rm -rf .github/workflows.backup  # If any backups exist
```

### Step 6: Verify Cleanup
```bash
git ls-files | grep -E "\.github/workflows|\.github/actions" | wc -l  # Should be 0
```

---

## 10. ENFORCEMENT MECHANISM

### Pre-Commit Hook (Automatic Blocking)
**Location:** `.githooks/prevent-workflows`
```bash
#!/bin/bash
# Block commits that add/modify GitHub Actions
if git diff --cached --name-only | grep -E "\.github/workflows|secrets"; then
  echo "❌ ERROR: GitHub Actions and secrets cannot be committed"
  exit 1
fi
```

### Violations & Remediation:
| Violation | Severity | Response | Timeline |
|-----------|----------|----------|----------|
| GitHub Actions workflow found | CRITICAL | Immediate removal | 30 min |
| GitHub Secrets used | CRITICAL | Remove + migrate to GSM/Vault/KMS | 1 hour |
| Plaintext credentials in script | CRITICAL | Remove + rotate credentials | 15 min |
| GitHub release created | HIGH | Delete release + document properly | 24 hours |

---

## 11. COMPLIANCE CHECKLIST

### Weekly:
- [ ] No GitHub Actions workflows present
- [ ] All secrets from GSM/Vault/KMS
- [ ] Direct deployments executing successfully
- [ ] Audit logs accumulating

### Monthly:
- [ ] Secret rotation completed (30-day cycle)
- [ ] Audit logs reviewed
- [ ] No unauthorized deployments
- [ ] Key rotation verified working

### Quarterly:
- [ ] Full credential audit
- [ ] Policy review & updates
- [ ] Team training on direct deployment
- [ ] Security incident review

---

## 12. CONTACT & ESCALATION

**For assistance with:**
- Direct deployment setup: Platform Engineering
- Secret rotation: Security team
- Emergency credentials: On-call SecOps
- Policy questions: Platform Engineering

**Violation reporting:**
- Contact: @ops-admin (GitHub)
- Severity: CRITICAL (immediate action required)

---

## Sign-Off

- **Status:** ✅ **ACTIVE & ENFORCED**
- **Effective:** 2026-03-10
- **Authority:** Self-Hosted Runner Direct Deployment Framework
- **Violations:** Zero tolerance
- **Next Review:** 2026-04-10

**Any GitHub Actions detected = IMMEDIATE REMOVAL & REMEDIATION**
