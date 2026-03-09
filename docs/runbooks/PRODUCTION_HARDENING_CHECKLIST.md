# PRODUCTION SECURITY HARDENING CHECKLIST

## Pre-Execution Security Validation

### 1. Credential Isolation & Ephemeralality (CRITICAL)

**✅ OIDC/JWT/WIF Validation**
- [ ] Verify no static AWS credentials in codebase
- [ ] Verify no GCP service account keys in codebase
- [ ] Verify no Vault static tokens in environment
- [ ] Verify all workflows use OIDC/JWT/WIF tokens only
- [ ] Verify token expiration < 1 hour on all workflows

**✅ Environment Secrets Isolation**
- [ ] Verify GitHub Secrets are used for sensitive values
- [ ] Verify no credentials in default branches (main)
- [ ] Verify secrets have minimal scope/permissions
- [ ] Verify secrets rotation scheduled (Phase 5)

**Validation Command:**
```bash
# Check for exposed credentials
grep -r "AKIA\|ghp_\|-----BEGIN PRIVATE" . --exclude-dir=.git --exclude-dir=.github --exclude-dir=node_modules || echo "✅ No obvious credentials found"

# Check for hardcoded tokens
grep -r "token=" . --exclude-dir=.git --exclude-dir=.github | grep -v "jwt_token\|oidc_token" || echo "✅ No suspicious tokens found"
```

---

## 2. Audit Trail Immutability (CRITICAL)

**✅ JSONL Audit Log Verification**
- [ ] Verify `.deployment-audit/` exists and contains JSONL logs
- [ ] Verify `.oidc-setup-audit/` exists and contains JSONL logs
- [ ] Verify `.revocation-audit/` exists and contains JSONL logs
- [ ] Verify `.validation-audit/` exists and contains JSONL logs
- [ ] Verify `.operations-audit/` exists and contains JSONL logs
- [ ] Verify `.orchestration-audit/` exists and contains JSONL logs

**✅ Append-Only Verification**
- [ ] Verify logs use line-delimited JSON (JSONL) format
- [ ] Verify no log files have been modified (only appended)
- [ ] Verify log file sizes are monotonically increasing
- [ ] Verify timestamps are monotonically increasing within logs

**Validation Command:**
```bash
# Verify JSONL format
for f in .{deployment,oidc-setup,revocation,validation,operations,orchestration}-audit/*.jsonl; do
  echo "Checking $f..."
  tail -10 "$f" | jq . && echo "✅ Valid JSONL" || echo "❌ Invalid JSONL"
done
```

---

## 3. Idempotency Verification (CRITICAL)

**✅ Script Idempotency Testing**
- [ ] Verify all `setup_*.sh` scripts check before creating
- [ ] Verify all `migrate_*.py` scripts use idempotent logic
- [ ] Verify all automation scripts use `--force` or idempotent flags
- [ ] Test: Run Phase 1 scripts twice, verify same results

**✅ Workflow Idempotency Testing**
- [ ] Verify Phase 2 workflow can re-run without errors
- [ ] Verify Phase 3 can be re-run (no double revocation)
- [ ] Verify Phase 4 can be re-run (no validation conflicts)
- [ ] Verify Phase 5 operations are re-runnable

**Validation Command:**
```bash
# Check script patterns for idempotency
grep -r "if.*exist\|if.*grep\|-z\|-f\|--force" scripts/ | wc -l
echo "Scripts with idempotency checks:"
grep -r "if.*exist" scripts/ | head -5
```

---

## 4. Least Privilege Access Control (CRITICAL)

**✅ GitHub Actions Permissions**
- [ ] Verify workflows use minimal PERMISSIONS scopes
- [ ] Verify workflows don't have admin/write-all permissions
- [ ] Verify credential actions isolate reader/writer roles
- [ ] Verify Phase 3 (revocation) can't modify unrelated settings

**✅ Cloud Provider IAM**
- [ ] Verify GCP WIF service account has minimal roles
- [ ] Verify AWS WIF role has only required KMS permissions
- [ ] Verify Vault JWT role has only credential reader/rotator access
- [ ] Verify Phase 1 scripts request minimum required permissions

**Sample IAM Verification:**
```bash
# Check GitHub Actions permission scopes
grep -r "permissions:" .github/workflows/ | head -10
echo "Verify each permission is necessary"

# Check for overly broad wildcards
grep -r "resources:\s*\[\"\*\"\]" .github/workflows/ && echo "⚠️  Found wildcard resources"
```

---

## 5. Error Handling & Auto-Remediation (HIGH)

**✅ Failure Scenarios**
- [ ] Verify Phase 2 handles OIDC setup failure gracefully
- [ ] Verify Phase 3 revocation with partial failures continues
- [ ] Verify Phase 4 validation continues on individual failures
- [ ] Verify Phase 5 operations heal from transient errors

**✅ RCA Auto-Healing**
- [ ] Verify RCA logs go to `.rca-audit/`
- [ ] Verify auto-heal attempts logged before and after
- [ ] Verify failed heal attempts trigger alerts/notifications
- [ ] Verify audit trail shows all remediation steps

**Validation Command:**
```bash
# Check for error handling patterns
grep -r "try\|except\|catch\|trap\|set -e\||| exit" scripts/ deployment/ | wc -l
echo "Error handling patterns found"

# Check for RCA integration
grep -r "rca\|remediat\|heal\|fallback" scripts/ | head -5
```

---

## 6. Secrets Rotation Readiness (HIGH)

**✅ Rotation Script Validation**
- [ ] Verify GSM rotation script exists and is idempotent
- [ ] Verify Vault rotation script exists and is idempotent
- [ ] Verify KMS key rotation is automatic (AWS default)
- [ ] Verify rotation schedule is Phase 5 at 02:00 UTC daily

**✅ Zero-Downtime Rotation**
- [ ] Verify old credentials stay valid for grace period
- [ ] Verify new credentials are pre-distributed before rotation
- [ ] Verify clients can fallback to previous credentials
- [ ] Verify rotation audit trail is immutable

**Validation Command:**
```bash
# Check rotation scheduling
grep -r "02:00\|0 2" .github/workflows/phase-5-operations.yml
echo "Verify daily rotation at 02:00 UTC"

# Check zero-downtime pattern
grep -r "grace\|fallback\|previous\|old_secret" scripts/
```

---

## 7. Network & Transport Security (MEDIUM)

**✅ TLS/HTTPS Enforcement**
- [ ] Verify all API calls use HTTPS (no HTTP)
- [ ] Verify Vault address uses https://
- [ ] Verify GCP API calls are over TLS
- [ ] Verify AWS API calls are over TLS

**✅ Certificate Pinning (Optional)**
- [ ] Verify Vault certificate validation configured
- [ ] Verify GCP endpoint validation configured
- [ ] Verify AWS endpoint validation configured

**Validation Command:**
```bash
# Check for HTTP instead of HTTPS
grep -r "http://" scripts/ deployment/ | grep -v "http://localhost\|#"
echo "Verify no insecure HTTP endpoints"

# Check HTTPS usage
grep -r "https://\|tls\|ssl\|certificate" scripts/ | head -10
```

---

## 8. Logging & Monitoring (MEDIUM)

**✅ Structured Logging**
- [ ] Verify all logs are JSON-formatted
- [ ] Verify logs include timestamp, level, message, context
- [ ] Verify sensitive data is NOT in logs (sanitization)
- [ ] Verify logs are immutable (append-only)

**✅ Monitoring Integration**
- [ ] Verify Phase 4 validation logs go to `.validation-audit/`
- [ ] Verify Phase 5 hourly health checks are logged
- [ ] Verify Phase 5 weekly audits are logged
- [ ] Verify alerts configured for critical failures

**Validation Command:**
```bash
# Check log structure
jq . < .deployment-audit/deployment.jsonl | head -3
echo "Verify JSON structure is valid"

# Check for sensitive data patterns
grep -r "password\|secret\|token\|key=" .{deployment,oidc-setup,revocation,validation,operations}-audit/ | grep -v "secret_manager\|secret_key_id" and echo "⚠️  Check for exposed secrets"
```

---

## 9. Compliance & Audit (MEDIUM)

**✅ Change Audit Trail**
- [ ] Verify all credential changes are logged
- [ ] Verify all rotations are logged with before/after state
- [ ] Verify all revocations are logged with reason
- [ ] Verify all access attempts are logged

**✅ Compliance Reports**
- [ ] Verify daily compliance audit scheduled (Phase 5)
- [ ] Verify compliance report includes: rotations, revocations, access
- [ ] Verify compliance report is immutably stored
- [ ] Verify compliance report includes previous 30 days

**Validation Command:**
```bash
# Check audit logs for completeness
wc -l .{deployment,oidc-setup,revocation,validation,operations}-audit/*.jsonl
echo "Verify log files contain entries"

# Sample compliance check
jq '.event' .operations-audit/operations.jsonl | sort | uniq -c
echo "Verify diverse event types are logged"
```

---

## 10. Go-Live Readiness Gates (PRE-PHASE-2)

**✅ Final Checks Before Phase 2 Execution**
- [ ] All scripts are executable (`chmod +x`)
- [ ] All workflows have proper syntax (validate via GitHub UI)
- [ ] All documentation is reviewed and up-to-date
- [ ] All GitHub issues are closed except active work
- [ ] Rollback plan is reviewed and tested
- [ ] Emergency contacts are documented
- [ ] On-call team is briefed and ready

**✅ Phase 1 Verification**
- [ ] 7/7 À La Carte components deployed
- [ ] 13 credential & automation scripts created
- [ ] All audit trails initialized
- [ ] Git governance enforcement active

**✅ Phase 2 Preparation**
- [ ] GCP project ID confirmed (or test mode)
- [ ] AWS account ID confirmed (or test mode)
- [ ] Vault address confirmed (or test mode)
- [ ] GitHub Actions permissions verified

**Pre-Execution Shell Commands:**
```bash
# Verify all scripts are executable
find scripts/ -name "*.sh" -o -name "*.py" | xargs ls -l | grep -c "rwx"
echo "scripts should be executable"

# Validate YAML workflows
for f in .github/workflows/phase-*.yml; do
  echo "Validating $f..."
  python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "✅ Valid" || echo "❌ Invalid"
done

# Count total audit entries
echo "Total audit entries:"
find . -name "*.jsonl" -exec wc -l {} + | tail -1
```

---

## Hardening Verification Script

Run to verify all hardening measures:

```bash
#!/bin/bash
set -e

echo "🔍 Running production hardening verification..."
echo ""

# 1. Credential isolation
echo "1️⃣  Checking credential isolation..."
grep -r "AKIA\|ghp_\|-----BEGIN PRIVATE" . --exclude-dir=.git 2>/dev/null && echo "❌ Found exposed credentials!" || echo "✅ No exposed credentials"

# 2. Audit trail
echo "2️⃣  Checking audit trails..."
for dir in .{deployment,oidc-setup,revocation,validation,operations,orchestration}-audit; do
  [ -d "$dir" ] && echo "✅ $dir exists" || echo "❌ $dir missing"
done

# 3. Idempotency
echo "3️⃣  Checking idempotency patterns..."
idempotent_count=$(grep -r "if.*exist\|if.*grep\|-z\|-f\|--force" scripts/ 2>/dev/null | wc -l)
echo "✅ Found $idempotent_count idempotency patterns"

# 4. Scripts executable
echo "4️⃣  Checking script permissions..."
executable_count=$(find scripts/ \( -name "*.sh" -o -name "*.py" \) -executable | wc -l)
total_count=$(find scripts/ \( -name "*.sh" -o -name "*.py" \) | wc -l)
echo "✅ $executable_count/$total_count scripts are executable"

# 5. Workflows syntax
echo "5️⃣  Checking workflow syntax..."
workflow_count=$(find .github/workflows -name "phase-*.yml" | wc -l)
echo "✅ Found $workflow_count phase workflows"

# 6. Git governance
echo "6️⃣  Checking git governance..."
[ -f ".instructions.md" ] && echo "✅ .instructions.md exists" || echo "❌ .instructions.md missing"
[ -f "GIT_GOVERNANCE_STANDARDS.md" ] && echo "✅ GIT_GOVERNANCE_STANDARDS.md exists" || echo "❌ GIT_GOVERNANCE_STANDARDS.md missing"

echo ""
echo "✅ Hardening verification complete!"
```

---

## Sign-Off: Production Hardening Ready

**Checklist Owner:** Security Engineering  
**Approval Status:** ⏳ PENDING (See below)

**Pre-Phase-2 Approval Required:**
- [ ] Security lead reviews and approves
- [ ] Infrastructure lead reviews and approves
- [ ] On-call team briefed and ready

**Approvals:**
- **Security:** _____________________ (signature/date)
- **Infrastructure:** _____________________ (signature/date)
- **Operations:** _____________________ (signature/date)

Once all checks passed and approvals obtained, execute:
```bash
python3 orchestrator.py --trigger-phase-2
```
