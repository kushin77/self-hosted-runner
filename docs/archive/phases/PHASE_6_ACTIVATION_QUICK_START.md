# PHASE 6 ACTIVATION QUICK START
## 🚀 Final Hands-Off Automation Activation Guide

**Status**: ✅ All Systems Deployed & Ready  
**Date**: March 7, 2026  
**Expected Time to Full Operations**: 30-60 minutes  

---

## 📋 TL;DR - Three Critical Actions

### 1️⃣ OPERATOR: Update GCP Key (5 min)

```bash
# Step 1: Validate locally (recommended)
bash scripts/validate-and-ingest-gcp-key.sh ~/Downloads/gcp-key.json

# Step 2: When validation succeeds, apply:
bash scripts/validate-and-ingest-gcp-key.sh ~/Downloads/gcp-key.json --apply

# Step 3: Verify update (wait 5-10 seconds first)
gh secret list --repo kushin77/self-hosted-runner | grep GCP_SERVICE_ACCOUNT_KEY
```

### 2️⃣ OPERATOR: Activate Cascade (1 min)

```bash
# After GCP key is updated, trigger automation:
gh issue comment 1239 --body "ingested: true" --repo kushin77/self-hosted-runner

# Or use GitHub web UI:
# Go to: https://github.com/kushin77/self-hosted-runner/issues/1239
# Comment: ingested: true
```

### 3️⃣ ADMIN: Provision Secrets (15-20 min, can run in parallel)

See: [SECRETS_SETUP_GUIDE.md](https://github.com/kushin77/self-hosted-runner/blob/main/SECRETS_SETUP_GUIDE.md)

Required secrets:
- `DEPLOY_SSH_KEY` - SSH private key for Ansible
- `RUNNER_MGMT_TOKEN` - GitHub PAT with repo + hooks scope
- `GCP_SERVICE_ACCOUNT_KEY` - (from step 1 above)

---

## ✅ Automated Activation System

Run the comprehensive activation checker anytime:

```bash
bash scripts/activate-phase-6-automation.sh
```

**Options:**
```bash
--skip-operator    # Skip operator checks
--skip-admin       # Skip admin checks  
--verify-only      # Check status without triggering
```

---

## 🎯 What Happens After Activation

```
Timeline (Total: 2-3 minutes from operator comment)

T+0s   : Operator comments "ingested: true"
  ↓
T+5s   : auto-ingest-trigger detects comment
  ↓
T+10s  : Posts acknowledgment comment
  ↓
T+15s  : Dispatches verify-secrets workflow
  ↓
T+20s  : Dispatches dr-smoke-test workflow (parallel)
  ↓
T+1m   : Verify workflow validates GCP key
  ↓
T+2m   : DR smoke test validates Docker + GCP
  ↓
T+2.5m : Results posted to Issue #1239
  ↓
T+3m   : Issue auto-closes with success message
  ↓
System fully operational ✓
  - Security audits: Every 6 hours
  - Vulnerability remediation: Daily 2 AM UTC
  - Auto-retry monitoring: Every 15 minutes
  - Zero manual intervention: 100% hands-off
```

---

## 📊 Pre-Activation Checklist

Before activation, verify:

- [ ] All 5 workflows deployed: `gh workflow list --repo kushin77/self-hosted-runner`
- [ ] GCP key is valid JSON: `bash scripts/validate-and-ingest-gcp-key.sh key.json`
- [ ] GitHub CLI authenticated: `gh auth status`
- [ ] Repository access verified: `gh repo view kushin77/self-hosted-runner`

---

## 🔗 Key Issues & Resources

| Issue | Purpose | Owner | Status |
|-------|---------|-------|--------|
| [#1202](https://github.com/kushin77/self-hosted-runner/issues/1202) | GCP key invalid | Operator | 🔴 CRITICAL |
| [#1239](https://github.com/kushin77/self-hosted-runner/issues/1239) | Operator activation trigger | Operator | ⏳ Awaiting comment |
| [#1259](https://github.com/kushin77/self-hosted-runner/issues/1259) | Admin secrets provisioning | Admin | 🟡 HIGH |
| [#1277](https://github.com/kushin77/self-hosted-runner/issues/1277) | Master meta-issue | Reference | 📚 Context |

---

## 📚 Documentation

- **Operator Playbook**: [HANDS_OFF_OPERATOR_PLAYBOOK.md](../../runbooks/HANDS_OFF_OPERATOR_PLAYBOOK.md)
- **Secrets Setup**: [SECRETS_SETUP_GUIDE.md](../../runbooks/SECRETS_SETUP_GUIDE.md)
- **Deploy Key Runbook**: [DEPLOY_KEY_REMEDIATION_RUNBOOK.md](../../runbooks/DEPLOY_KEY_REMEDIATION_RUNBOOK.md)
- **CI/CD Governance**: [CI_CD_GOVERNANCE_GUIDE.md](../../runbooks/CI_CD_GOVERNANCE_GUIDE.md)

---

## 🚨 Troubleshooting

### GCP Key Validation Fails

```bash
# Check JSON syntax:
jq . ~/Downloads/gcp-key.json

# If error, key is malformed. Fix in source system first.

# Validate required fields:
jq '{type, project_id, client_email}' ~/Downloads/gcp-key.json
# Must have: type="service_account", project_id and client_email present
```

### Operator Comment Not Triggering

Check Issue #1239 comments:
- Is your comment on the correct issue?
- Is comment text exactly: `ingested: true`?
- Did you wait 5-10 seconds after secret update?

Manual trigger (if needed):
```bash
gh workflow run auto-ingest-trigger.yml --repo kushin77/self-hosted-runner --ref main
```

### DR Tests Still Failing

Check Issue #1194:
- Requires valid GCP key (linked to #1202)
- May take 2-3 workflow runs to pass
- Auto-retry polls every 15 minutes

---

## ✨ Success States

**After activation, you should see:**

✅ **Verify Workflow**
- GCP key validation: PASS
- JSON schema check: PASS
- Project ID present: PASS  
- Private key valid: PASS

✅ **DR Smoke Test**
- Docker registry access: PASS
- GCP auth check: PASS
- Backup readiness: PASS

✅ **Issue #1239**
- Status updated: ✓
- Auto-closed: ✓
- Comments include success details: ✓

---

## 📞 Support

**Cannot proceed?**
1. Check the specific issue linked above
2. Review the remediation comments
3. Run: `bash scripts/activate-phase-6-automation.sh --verify-only`
4. Comment on relevant issue with diagnostics

**Questions about automation?**
- See HANDS_OFF_OPERATOR_PLAYBOOK.md
- See SECRETS_SETUP_GUIDE.md
- See CI_CD_GOVERNANCE_GUIDE.md

**Edge cases?**
- Escalations documented in Issue #1268, #1276
- GitHub support contact info in escalation issues

---

## 🎯 Remember

**After activation:**
- ✅ All automation is 100% hands-off
- ✅ Security audits run automatically
- ✅ Vulnerabilities auto-remediated daily
- ✅ Status monitored every 15 minutes
- ✅ Zero manual touchpoints required
- ✅ All changes immutable in Git
- ✅ Audit trail in GitHub Issues

**You have built a true autonomous system. Enjoy! 🚀**

---

**Last Updated**: March 7, 2026  
**Next Review**: March 14, 2026 (1 week, after first full cycle)  
**Phase**: 6 - Hands-Off Automation  
**Status**: ✅ READY FOR ACTIVATION
