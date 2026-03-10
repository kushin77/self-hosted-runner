# Framework v1.0 - Go-Live Operations Runbook

**Release Date:** March 10, 2026  
**Status:** 🟢 PRODUCTION LIVE  
**Authorization:** Immediate Copilot Deployment Granted

---

## Executive Summary

Framework v1.0 is now LIVE and OPERATIONAL. This runbook provides step-by-step procedures for team deployment, ongoing operations, and emergency response.

**All 8 Framework Principles Operational:**
- ✅ Immutable (JSONL append-only logs forever)
- ✅ Ephemeral (create/destroy per deployment)
- ✅ Idempotent (safe for re-execution)
- ✅ No-Ops (zero manual intervention)
- ✅ Hands-Off (fire-and-forget model)
- ✅ GSM/Vault/KMS (three-tier fallback)
- ✅ Direct Deployment (SSH scripts only)
- ✅ No GitHub Actions (zero tolerance enforced)

---

## SECTION 1: IMMEDIATE TEAM DEPLOYMENT (Day 1)

### Step 1.1: Documentation Review (Start: 09:00, End: 11:00)

**Team Assignment:** All members  
**Time Allocation:** 2 hours  
**Location:** docs/governance/

**Required Documents:**

| Document | Time | Priority |
|----------|------|----------|
| NO_GITHUB_ACTIONS_POLICY.md | 15 min | CRITICAL |
| DIRECT_DEPLOYMENT_FRAMEWORK.md | 20 min | CRITICAL |
| MULTI_CLOUD_CREDENTIAL_MANAGEMENT.md | 25 min | CRITICAL |
| IMMUTABLE_AUDIT_TRAIL_SYSTEM.md | 20 min | HIGH |
| FOLDER_GOVERNANCE_STANDARDS.md | 10 min | HIGH |

**Verification:** Each team member documents 3 key learnings

### Step 1.2: Certification Exam (Start: 11:00, End: 12:00)

**Team Assignment:** All members (parallel track)  
**Location:** GitHub Issue #2277  
**Pass Requirement:** 80% (24/30 questions)

**Topics Covered:**
1. NO GitHub Actions policy (5 questions)
2. Direct deployment framework (8 questions)
3. Credential management (GSM/Vault/KMS) (8 questions)
4. Immutable audit trail (6 questions)
5. Framework principles (3 questions)

**Process:**
```bash
# Open Issue #2277
# Complete exam form
# Submit answers
# Verify 80% pass
# Document score
```

**SLA:** All team members must pass before production deployment (same day if possible, next day max)

### Step 1.3: Staging Deployment Test (Start: 13:00, End: 13:30)

**Team Assignment:** Deployment engineers + 1 observer  
**System:** Staging environment  
**Success Criteria:** All health checks pass

**Procedure:**

```bash
cd /home/akushnir/self-hosted-runner

# Test 1: Verify framework before deployment
echo "=== Pre-deployment Verification ==="
git config core.hooksPath              # Should be: .githooks
find .github/workflows -name "*.yml" | wc -l  # Should be: 0
test -x .githooks/prevent-workflows && echo "✅ Pre-commit hook active"

# Test 2: Deploy to staging
echo "=== Deploying to Staging ==="
./scripts/deployment/deploy-to-staging.sh
DEPLOY_CODE=$?
echo "Deployment exit code: $DEPLOY_CODE"

# Test 3: Verify deployment
echo "=== Verifying Audit Trail ==="
tail -5 logs/deployments/$(date +%Y-%m-%d).jsonl | jq '.'

# Test 4: Confirm health checks
echo "=== Health Check ==="
# (Health checks run as part of deployment)
# Expected: All services running, all checks passing

# Test 5: Test credential fallback (manual)
echo "=== Testing Credential Fallback ==="
echo "Primary (GSM): $(gcloud secrets versions access latest --secret=test-secret 2>/dev/null || echo 'fallback')"
echo "Vault: $(vault kv get -field=value secret/test 2>/dev/null || echo 'fallback')"
echo "KMS: $(aws secretsmanager get-secret-value --secret-id test 2>/dev/null || echo 'not available')"
```

**Expected Output:**
- Exit code 0
- Audit entries in logs/deployments/
- All health checks passing
- No errors in logs

**If Any Test Fails:**
1. Check logs/deployments/ for error details
2. Review error message
3. Fix issue (documentation reference)
4. Re-test (idempotent - safe to run again)
5. Escalate to @deployment-team if unresolved

### Step 1.4: Production Deployment (Start: 14:00)

**Team Assignment:** Senior deployment engineer + witness  
**System:** Production environment  
**Rollback Plan:** Previous version available via git revert

**Pre-Deployment Checklist:**

- [ ] All team members passed certification exam
- [ ] Staging deployment successful
- [ ] Credential fallback tested working
- [ ] Pre-commit hook active
- [ ] Audit trail operational
- [ ] Runbook reviewed and understood
- [ ] Emergency contacts identified
- [ ] Monitoring configured

**Deployment Procedure:**

```bash
cd /home/akushnir/self-hosted-runner

# Step 1: Verify production readiness
echo "=== Production Readiness Check ==="
git log -1 --oneline
git status                    # Should be: clean
git config core.hooksPath    # Should be: .githooks

# Step 2: Execute production deployment
echo "=== Deploying to Production ==="
./scripts/deployment/deploy-to-production.sh
DEPLOY_CODE=$?

# Step 3: Verify deployment success
if [ $DEPLOY_CODE -eq 0 ]; then
  echo "✅ Deployment successful (exit code 0)"
  
  # Step 4: Verify audit trail entry
  echo "=== Verifying Audit Entry ==="
  tail -1 logs/deployments/$(date +%Y-%m-%d).jsonl | jq '.'
  
  # Step 5: Run health checks
  echo "=== Running Health Checks ==="
  # (Auto-run as part of deployment)
  
  # Step 6: Notify team
  echo "✅ PRODUCTION DEPLOYMENT SUCCESSFUL"
  
else
  echo "❌ Deployment failed (exit code $DEPLOY_CODE)"
  echo "INITIATING ROLLBACK..."
  git revert HEAD --no-edit
  git push origin main
  echo "⚠️ Rollback complete. Escalating to @deployment-team"
fi
```

**Post-Deployment Verification (30 minutes):**

```bash
# Check system health
curl https://production-endpoint/health

# Verify audit trail growing
watch 'tail -3 logs/deployments/$(date +%Y-%m-%d).jsonl | jq .'

# Check error logs
tail -20 logs/error.log

# Verify credentials working (spot check)
./scripts/deployment/test-credential-fallback.sh
```

**Success Criteria:**
- ✅ Exit code 0
- ✅ All health checks passing
- ✅ Audit entries recorded
- ✅ No error logs
- ✅ System stable for 30 minutes

**SLA:** 15 minutes from deployment start to "all systems operational" status

---

## SECTION 2: ONGOING OPERATIONS (Weekly)

### Monthly Compliance Tasks

**1st Friday of Month: NO GitHub Actions Verification (Issue #2274)**

```bash
# Run verification
find .github/workflows -name "*.yml" 2>/dev/null | wc -l  # Should be: 0
git log --all --oneline | grep -i "workflow\|github action" | wc -l  # Should be: 0
test -x .githooks/prevent-workflows && echo "✅ Hook active"

# Document results
echo "Date: $(date)" >> logs/compliance.log
echo "GitHub Actions: $(find .github/workflows -name '*.yml' | wc -l) (target: 0)" >> logs/compliance.log
echo "Status: PASS/FAIL" >> logs/compliance.log
```

**2nd Friday of Month: Credential Rotation Validation (Issue #2275)**

```bash
# Trigger automatic rotation
./scripts/provisioning/rotate-secrets.sh

# Verify all 3 sources rotated
grep "credential_rotation" logs/credential-rotations/$(date +%Y-%m-%d).jsonl | jq '.'

# Test new credentials work
./scripts/deployment/test-credential-fallback.sh
```

**3rd Friday of Month: Audit Trail Integrity (Issue #2276)**

```bash
# Verify immutability
sha256sum -c logs/checksums.sha256

# Verify retention policy
find logs -type f -name "*.jsonl" | wc -l  # Should increase over time

# Test log querying performance
time grep "deployment_complete" logs/deployments/*.jsonl | wc -l
```

**Last Thursday of Month: Team Training Refresher (Issue #2277)**

- 30-minute review of policy updates
- New team members take certification exam
- Q&A on framework implementation
- Discussion of lessons learned

### Weekly Status Report

Every Monday send brief status:

```
Subject: Framework v1.0 Weekly Status

Deployments:      [N] successful, [0] failed
GitHub Actions:   [0] detected
Credentials:      [✓] all sources operational
Audit Trail:      [N] entries recorded
Team Status:      All trained and operational
Issues:           [N] open, [0] critical
```

---

## SECTION 3: EMERGENCY PROCEDURES

### Credential Exposure Response (15-Minute SLA)

**Minute 0-3: Detection & Verification**
```bash
# If plaintext credential detected:
echo "[ALERT] Credential exposure detected: $CREDENTIAL_TYPE"
# Verify exposure confirmed
# Open #security-incidents channel
```

**Minute 3-10: Emergency Rotation**
```bash
cd /home/akushnir/self-hosted-runner
./scripts/provisioning/rotate-secrets.sh --emergency
# Rotates ALL credentials in all 3 sources simultaneously
# Logs to: logs/security-incidents/YYYY-MM-DD.jsonl
```

**Minute 10-12: Redeploy with New Credentials**
```bash
./scripts/deployment/deploy-to-production.sh --use-latest-credentials
# Forces pull of new credentials from all 3 sources
```

**Minute 12-15: Verification**
```bash
# Confirm all systems using new credentials
./scripts/deployment/test-credential-fallback.sh

# Verify no stale credentials in logs
grep -v "[USE_GSM_VAULT_KMS]" docs/**/*.md scripts/**/*.sh | grep -i "password\|secret\|token" | wc -l
# Should be 0 or minimal (only in templates)
```

**Post-Incident:**
- [ ] Document timeline in logs/security-incidents/
- [ ] Review how exposure occurred
- [ ] Update prevention measures
- [ ] Schedule team post-mortem
- [ ] Update GitHub issue #2275

### GitHub Actions Violation Response

**If Workflow Commit Detected:**

1. **Pre-commit hook blocks commit** (no action needed)
2. **If hook bypassed:**
   ```bash
   # Identify violating commit
   git log --all --oneline | grep -i "workflow\|github action"
   
   # Immediately revert
   git revert <commit-hash>
   git push origin main
   
   # Escalate to @security-incidents
   ```

3. **Investigation:**
   - Why was commit attempted?
   - Who made it and why?
   - Do they understand the NO GitHub Actions policy?
   - Update Issue #2274 with incident

---

## SECTION 4: TROUBLESHOOTING

### Deployment Fails

```bash
# 1. Check exit code
echo $?  # Non-zero means failure

# 2. Review audit trail
tail -20 logs/deployments/$(date +%Y-%m-%d).jsonl | jq '.[] | select(.status == "failed")'

# 3. Check deployment logs
cat logs/deployment.log | tail -50

# 4. Verify prerequisites
git config core.hooksPath          # Should be .githooks
find .github/workflows -name "*.yml" | wc -l  # Should be 0

# 5. Retry (idempotent - safe)
./scripts/deployment/deploy-to-production.sh

# 6. If still failing:
# - Escalate to @deployment-team
# - Include logs (from logs/ directory)
# - Include commit hash (git log -1 --oneline)
```

### Credential Fallback Not Working

```bash
# Test each source individually
echo "Testing GSM..."
gcloud secrets versions access latest --secret=test-secret

echo "Testing Vault..."
vault kv get -field=value secret/test

echo "Testing KMS..."
aws secretsmanager get-secret-value --secret-id=test

# If any source fails:
# - Check authentication (gcloud auth, vault login, aws configure)
# - Check credentials stored in respective system
# - Refer to MULTI_CLOUD_CREDENTIAL_MANAGEMENT.md
```

### Audit Trail Not Recording

```bash
# Check directory exists
ls -la logs/deployments/

# Check permissions
ls -l logs/deployments/$(date +%Y-%m-%d).jsonl

# If missing:
mkdir -p logs/deployments/
touch logs/deployments/$(date +%Y-%m-%d).jsonl

# Re-run deployment
./scripts/deployment/deploy-to-production.sh
```

---

## SECTION 5: QUICK REFERENCE

### Critical Commands

```bash
# Deploy to production
./scripts/deployment/deploy-to-production.sh

# Deploy to staging
./scripts/deployment/deploy-to-staging.sh

# Rotate credentials (30-day)
./scripts/provisioning/rotate-secrets.sh

# Emergency credential rotation
./scripts/provisioning/rotate-secrets.sh --emergency

# Check framework health
git config core.hooksPath
find .github/workflows -name "*.yml" | wc -l
test -x .githooks/prevent-workflows && echo "✅"

# View audit trail
tail -20 logs/deployments/$(date +%Y-%m-%d).jsonl | jq '.'

# Test credential fallback
./scripts/deployment/test-credential-fallback.sh
```

### Important Files

| Path | Purpose | Access |
|------|---------|--------|
| `.githooks/prevent-workflows` | NO GitHub Actions enforcement | Read-only |
| `.instructions.md` | Global policy enforcement | Read-only |
| `docs/governance/` | Governance documentation | Read-only |
| `logs/deployments/` | Immutable audit logs | Append-only |
| `logs/credential-rotations/` | Credential rotation logs | Append-only |
| `logs/security-incidents/` | Security event logs | Append-only |

### GitHub Issues (Ongoing)

| Issue | Schedule | Action |
|-------|----------|--------|
| #2274 | 1st Friday | NO GitHub Actions verification |
| #2275 | 2nd Friday | Credential rotation validation |
| #2276 | 3rd Friday | Audit trail integrity check |
| #2277 | Last Thursday | Team training refresher |

### Emergency Contacts

| Role | Contact | Channel |
|------|---------|---------|
| Deployment | @deployment-team | #deployment |
| Security | @security-team | #security |
| Compliance | @compliance-team | #compliance |
| Escalation | All teams | #security-incidents |

---

## Sign-Off

**Framework v1.0 Go-Live Operations Runbook**  
**Status:** LIVE & OPERATIONAL  
**Effective:** March 10, 2026  
**Authority:** Self-Hosted Runner Engineering Team

This runbook is the source of truth for all framework v1.0 operations. Keep updated as procedures evolve.

**Questions?** Refer to docs/governance/ or escalate to @platform-engineering-lead

