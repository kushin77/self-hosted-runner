# Automation Deployment Checklist

**Date**: March 7, 2026  
**Milestone**: Pre-Deployment Secrets & Configuration  
**Target**: Production Ready by EOD

---

## 🔐 ALL SECRETS SETUP

### ✅ Task 1: Generate & Set DEPLOY_SSH_KEY

```bash
chmod +x scripts/setup-automation-secrets-direct.sh
bash scripts/setup-automation-secrets-direct.sh
```

**Expected Output:**
```
✓ Authenticated
✓ SSH keypair generated
  Fingerprint: SHA256:xxxxxxxxxx
✓ DEPLOY_SSH_KEY set successfully
```

**Verify:**
```bash
gh secret list --repo kushin77/self-hosted-runner | grep DEPLOY_SSH_KEY
# Expected: DEPLOY_SSH_KEY          Updated 2026-03-07
```

---

### ✅ Task 2: Create & Set RUNNER_MGMT_TOKEN

**Step 2a: Generate GitHub PAT**

Navigate to: https://github.com/settings/tokens/new

Fill in:
- **Token name**: `runner-management-automation-2026-03`
- **Expiration**: 90 days
- **Scopes** (check these):
  - ✓ `repo` (full control of private repositories)
  - ✓ `admin:repo_hook` (full control of repository hooks)
  - ✓ `admin:org_hook` (full control of organization hooks, optional)

Click "Generate token" → Copy token immediately

**Step 2b: Set in GitHub Secrets**

```bash
# Replace with your actual token
gh secret set RUNNER_MGMT_TOKEN \
  --repo kushin77/self-hosted-runner \
  --body "ghp_YOUR_TOKEN_HERE"
```

**Verify:**
```bash
gh secret list --repo kushin77/self-hosted-runner | grep RUNNER_MGMT_TOKEN
# Expected: RUNNER_MGMT_TOKEN       Updated 2026-03-07
```

**Test Token:**
```bash
export GH_TOKEN="ghp_YOUR_TOKEN_HERE"
gh api /repos/kushin77/self-hosted-runner/actions/runners | head -20
# Expected: JSON with runners list (or empty list if no runners)
```

---

### ✅ Task 3: Add Public Key to Runner Hosts

After setting `DEPLOY_SSH_KEY`, get the public key:

```bash
# Get public key from GitHub secret (you'll need to save it during Step 1)
cat ~/.ssh/runner_deploy_key.pub  # If you saved it locally

# Or from the output above
```

For each runner host:

```bash
ssh runner-user@runner-host << 'EOF'
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add the public key
echo "SSH_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Verify
ls -la ~/.ssh/authorized_keys
EOF
```

**Test Connection:**
```bash
ssh -i ~/.ssh/runner_deploy_key runner-user@runner-host "echo 'SSH access works!'"
```

---

## 🚀 DEPLOYMENT

### ✅ Task 4: Merge PR #1013

```bash
gh pr merge 1013 --repo kushin77/self-hosted-runner --squash
```

This adds:
- `.github/workflows/secret-rotation-mgmt-token.yml` - Monthly secret validation
- `scripts/runner/runner-ephemeral-cleanup.sh` - Ephemeral state enforcement
- `scripts/automation/validate-idempotency.sh` - Idempotency validation
- Updated `scripts/runner/auto-heal.sh` - Enhanced with ephemeral cleanup
- Documentation files

---

### ✅ Task 5: Enable Workflows

```bash
# Verify workflows are enabled
gh workflow list --repo kushin77/self-hosted-runner

# Enable if needed (they should auto-enable on merge)
gh workflow enable runner-self-heal.yml --repo kushin77/self-hosted-runner
gh workflow enable admin-token-watch.yml --repo kushin77/self-hosted-runner
gh workflow enable secret-rotation-mgmt-token.yml --repo kushin77/self-hosted-runner
```

---

### ✅ Task 6: Trigger Initial Test Run

```bash
# Test runner-self-heal
gh workflow run runner-self-heal.yml \
  --repo kushin77/self-hosted-runner \
  --ref main

# Monitor
echo "Waiting for workflow to start..."
sleep 5
gh run list --workflow runner-self-heal.yml --repo kushin77/self-hosted-runner --limit 1
```

**Check Logs:**
```
Repository → Actions → runner-self-heal → [latest run] → View logs
```

---

### ✅ Task 7: Validate Idempotency

```bash
bash scripts/automation/validate-idempotency.sh
```

**Expected Output:**
```
=== IDEMPOTENCY VALIDATION START ===
✓ Syntax valid: ci_retry.sh
✓ Error handling guard present: ci_retry.sh
...
=== IDEMPOTENCY VALIDATION PASSED ===
```

---

## 📋 Pre-Deployment Verification

Before marking complete, verify all items:

- [ ] `DEPLOY_SSH_KEY` set in GitHub Secrets
- [ ] `RUNNER_MGMT_TOKEN` set in GitHub Secrets
- [ ] Public key added to all runner hosts
- [ ] SSH connection tested: `ssh -i runner_deploy_key runner@host echo OK`
- [ ] PR #1013 created and ready to merge
- [ ] All workflows appear in Actions tab
- [ ] Initial test run of runner-self-heal.yml succeeds
- [ ] Idempotency validation passes
- [ ] Documentation reviewed: [SECRETS_SETUP_GUIDE.md](SECRETS_SETUP_GUIDE.md)

---

## 🔄 Post-Deployment Monitoring (First 24 Hours)

After merging PR #1013:

### Hour 1-5: Initial Stability
- [ ] Monitor `runner-self-heal.yml` runs (5-min interval)
- [ ] Check workflow logs for errors
- [ ] Verify no unexpected failures

### Hour 6-12: Failure Detection
- [ ] Trigger a test failure (if safe to do)
- [ ] Verify `admin-token-watch.yml` auto-reruns
- [ ] Check exponential backoff works

### Hour 12-24: Secret Validation
- [ ] (If scheduled) Monitor `secret-rotation-mgmt-token.yml` if it runs
- [ ] Verify token health check passes

---

## 🎯 Success Criteria

✅ System is **PRODUCTION READY** when:

1. **Secrets Configured**
   - `DEPLOY_SSH_KEY` in GitHub ✓
   - `RUNNER_MGMT_TOKEN` in GitHub ✓
   - Public key on runner hosts ✓

2. **Automation Active**
   - runner-self-heal.yml runs every 5 min ✓
   - admin-token-watch.yml triggers on issues ✓
   - secret-rotation-mgmt-token.yml runs monthly ✓

3. **No Errors**
   - All workflows succeed ✓
   - Logs show valid operations ✓
   - No 403/401 auth failures ✓

4. **Auto-Recovery Works**
   - Offline runner recovered within 5 min ✓
   - Failed workflow auto-rerun succeeds ✓
   - Idempotency confirmed ✓

---

## 📞 Troubleshooting Quick Links

| Issue | Solution |
|-------|----------|
| "gh: command not found" | Install GitHub CLI: `apt-get install gh` |
| "Not authenticated" | Run `gh auth login` |
| "RUNNER_MGMT_TOKEN not set" | Create PAT at https://github.com/settings/tokens/new |
| "SSH key rejected" | Add public key to `~/.ssh/authorized_keys` on runner |
| "Workflow fails with 403" | Check token scopes: https://github.com/settings/tokens |
| "auto-heal.sh errors" | Check logs: `gh run view <RUN_ID> --log` |

---

## 📊 Timeline

| Phase | Duration | Status |
|-------|----------|--------|
| Generate SSH key | 1 min | ✅ Ready |
| Create GitHub PAT | 5 min | ⏳ Manual step |
| Set secrets | 2 min | ✅ Automated |
| Add pub key to hosts | 5 min | ⏳ Manual/script |
| Merge PR #1013 | 1 min | ⏳ Ready to merge |
| Test run | 5 min | ⏳ After merge |
| 24-hour monitor | 1440 min | ⏳ After deploy |

**Estimated Total Time: ~20 minutes**

---

## 🎉 Final Checklist

**When all items complete:**

1. ✅ Create final sign-off issue in GitHub
2. ✅ Tag PR #1013 as tested & approved
3. ✅ Merge to main
4. ✅ Update PHASE_3_4_HANDOFF_SUMMARY.md with "COMPLETE" status
5. ✅ Archive secrets setup documentation
6. ✅ Schedule next PAT rotation reminder (90 days from today)

---

**Prepared By**: GitHub Copilot (Automation Team)  
**Date**: March 7, 2026  
**Status**: Ready for Execution  
**Next Review**: March 8, 2026 (24h after deployment)
