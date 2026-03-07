---
title: Hands-Off Automation Operator Playbook
version: 1.0
date: 2026-03-07
status: Production Ready
---

# Hands-Off Automation Operator Playbook

## 🎯 Purpose

This playbook provides operators with clear, actionable procedures to activate, monitor, and manage the fully automated self-hosted runner infrastructure. The system is designed to require **minimal human intervention** after initial secret provisioning.

---

## 📋 Quick Start (3 Steps)

### Step 1: Validate & Ingest GCP Service Key

```bash
# On your local machine, validate the GCP service account key
cd /home/akushnir/self-hosted-runner
./scripts/ingest-gcp-key-safe.sh /path/to/your/gcp-sa-key.json

# Output should show: ✅ Valid GCP service account key (email: service-account@project.iam.gserviceaccount.com)
```

### Step 2: Store Secret in GitHub

```bash
# Copy the key into the repository secret
gh secret set GCP_SERVICE_ACCOUNT_KEY \
  --repo kushin77/self-hosted-runner \
  < /path/to/your/gcp-sa-key.json

# Verify the secret was stored (shows *** if successful)
gh secret list --repo kushin77/self-hosted-runner | grep GCP_SERVICE_ACCOUNT_KEY
```

### Step 3: Activate Automation Cascade

```bash
# Comment on Issue #1239 to trigger the automation cascade
gh issue comment 1239 \
  --repo kushin77/self-hosted-runner \
  --body "ingested: true"

# Watch the automation run (checks issue every 5 seconds)
watch -n 5 "gh run list --workflow auto-ingest-trigger.yml \
  --repo kushin77/self-hosted-runner --limit 1 \
  --json status,conclusion,createdAt"
```

---

## 🤖 What Happens After Activation

After you post the comment above, the **fully hands-off cascade** begins:

```
[Operator posts comment] 
         ↓
[auto-ingest-trigger detects comment] 
         ↓
[Dispatches verify-secrets + DR smoke test in parallel] 
         ↓
[Both run to completion] 
         ↓
[Results posted back to Issue #1239] 
         ↓
[If all pass: system fully operational] 
         ↓
[If issues: auto-retry posts reminders every 15 minutes]
```

**No manual steps required after the comment.** The system runs everything automatically.

---

## 📊 Monitoring

### Real-Time Workflow Status

```bash
# Watch latest 5 workflow runs
watch -n 10 "gh run list --repo kushin77/self-hosted-runner --limit 5 \
  --json number,name,status,conclusion,createdAt \
  --template='{{range .}}[{{.number}}] {{.name}}: {{.status}} ({{.conclusion}}) - {{.createdAt}}\n{{end}}'"
```

### Check Issue #1239 Status

```bash
# View the activation issue (will have cascade results posted as comments)
gh issue view 1239 --repo kushin77/self-hosted-runner
```

### Health Dashboard (All Workflows)

```bash
# See all 5 core workflows and their recent runs
for workflow in \
  "security-audit.yml" \
  "auto-ingest-trigger.yml" \
  "verify-secrets-and-diagnose.yml" \
  "dr-smoke-test.yml" \
  "auto-activation-retry.yml"; do
  echo "=== $workflow ===" 
  gh run list --workflow "$workflow" --repo kushin77/self-hosted-runner \
    --limit 3 --json status,conclusion,createdAt
done
```

---

## 🔴 If Something Goes Wrong

### Symptom 1: Verify Workflow Fails with "Invalid GCP Key"

**Diagnosis:**
```bash
# Check the error logs
gh run view <run-id> --repo kushin77/self-hosted-runner --log | grep -A 20 "error\|failed"
```

**Remediation:**
1. Validate your GCP key file:
   ```bash
   jq . /path/to/your/gcp-sa-key.json  # Should output valid JSON
   ```
2. Re-ingest the key:
   ```bash
   gh secret set GCP_SERVICE_ACCOUNT_KEY < /path/to/your/gcp-sa-key.json
   ```
3. Re-comment on Issue #1239:
   ```bash
   gh issue comment 1239 --body "ingested: true" --repo kushin77/self-hosted-runner
   ```
4. Wait 15 minutes for auto-retry OR manually dispatch:
   ```bash
   gh workflow run auto-activation-retry.yml --repo kushin77/self-hosted-runner --ref main
   ```

### Symptom 2: DR Smoke Test Fails

**Diagnosis:**
```bash
gh run view <dr-run-id> --repo kushin77/self-hosted-runner --log | grep -i "docker\|gcp\|error"
```

**Common Causes & Fixes:**

| Cause | Fix |
|-------|-----|
| GCP authentication failed | Re-check GCP key (Symptom 1 remediation) |
| Docker daemon unavailable | SSH to runner, restart docker: `systemctl restart docker` |
| Network connectivity issue | Check runner can reach GCP/registry endpoints |
| GCP quota exceeded | Check GCP project quotas; request increase if needed |

### Symptom 3: Auto-Activation-Retry Not Posting Updates

**Diagnosis:**
```bash
# Check the scheduled workflow is running
gh workflow list --repo kushin77/self-hosted-runner | grep auto-activation-retry

# View recent runs
gh run list --workflow auto-activation-retry.yml --repo kushin77/self-hosted-runner --limit 5
```

**Remediation:**
```bash
# Manually dispatch the retry workflow
gh workflow run auto-activation-retry.yml --repo kushin77/self-hosted-runner --ref main

# Or enable it in the UI if disabled:
# GitHub Settings → Actions → Workflows → auto-activation-retry.yml → Enable
```

---

## 🔑 Secret Management

### Secrets Used by Automation

| Secret | Purpose | Required | How to Provide |
|--------|---------|----------|-----------------|
| `GCP_SERVICE_ACCOUNT_KEY` | GCP authentication | ✅ Yes | `gh secret set GCP_SERVICE_ACCOUNT_KEY < key.json` |
| `VAULT_ADDR` | HashiCorp Vault endpoint | ⭕ Optional | GitHub Settings → Secrets |
| `VAULT_TOKEN` | Vault authentication | ⭕ Optional | GitHub Settings → Secrets |
| `SLACK_WEBHOOK_URL` | Slack notifications | ⭕ Optional | GitHub Settings → Secrets |

### Rotating Secrets

To rotate a secret safely:

```bash
# 1. Generate new secret value
# ... (obtain new GCP key, Vault token, etc.)

# 2. Update the secret
gh secret set SECRET_NAME --repo kushin77/self-hosted-runner < new-value

# 3. Trigger a workflow to validate (if applicable)
gh workflow run verify-secrets-and-diagnose.yml --repo kushin77/self-hosted-runner --ref main

# 4. Monitor results
gh run view --repo kushin77/self-hosted-runner --last
```

---

## 📅 Scheduled Maintenance

### Daily Auto-Runs

| Schedule | Workflow | Purpose |
|----------|----------|---------|
| **Every 15 min** | `auto-activation-retry.yml` | Monitor status, post reminders if blocked |
| **Every 6 hours** | `security-audit.yml` | Gitleaks + Trivy security scanning |
| **Every 24 hours** | `dr-smoke-test.yml` | Disaster recovery readiness validation |

### Manual Dispatch (Advanced)

```bash
# Run verification manually
gh workflow run verify-secrets-and-diagnose.yml \
  --repo kushin77/self-hosted-runner \
  --ref main

# Run security audit immediately
gh workflow run security-audit.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f scan_docker_images=true

# Run DR smoke test explicitly
gh workflow run dr-smoke-test.yml \
  --repo kushin77/self-hosted-runner \
  --ref main
```

---

## 🎯 Success Criteria

The system is **fully operational** when:

✅ Issue #1239 shows comments from both `verify-secrets-and-diagnose` and `dr-smoke-test`  
✅ Both workflows conclude with `success`  
✅ GCP service account is authenticated  
✅ Docker registry (docker.io) is reachable  
✅ DR smoke test passes (GCP resources responsive)  

---

## 🚨 Emergency Procedures

### If Workflows Are Stuck/Not Running

1. **Check GitHub Actions status:**
   ```bash
   # GitHub Status API
   curl https://www.githubstatus.com/api/v2/summary.json | jq .
   ```

2. **Restart workflow:**
   ```bash
   # Re-dispatch manually
   gh workflow run auto-ingest-trigger.yml --repo kushin77/self-hosted-runner --ref main
   ```

3. **Force a cascade retry:**
   ```bash
   # This will re-trigger all downstream workflows
   gh issue comment 1239 \
     --repo kushin77/self-hosted-runner \
     --body "ingested: true  # Retry cascade"
   ```

4. **Check runner availability:**
   ```bash
   # If using self-hosted runners
   gh runner list --repo kushin77/self-hosted-runner
   ```

### If Auto-Escalation Not Working

1. **Verify Slack webhook (if configured):**
   ```bash
   # Test webhook manually
   curl -X POST "$SLACK_WEBHOOK_URL" \
     -H 'Content-Type: application/json' \
     -d '{"text":"Test message from automation"}'
   ```

2. **Check GitHub issue notification settings:**
   - Ensure repo notifications are enabled
   - Check personal notification preferences

---

## 📖 Architecture Overview

The system has **5 core workflows** that work together:

```
┌─────────────────────────────────────────────┐
│         Hands-Off Automation Stack          │
├─────────────────────────────────────────────┤
│                                             │
│  [auto-activation-retry]                    │
│    Monitors & posts reminders every 15m     │
│           ↓                                 │
│  [auto-ingest-trigger] ← Operator comment   │
│    Detects activation signal                │
│           ↓                                 │
│    ┌─────┴──────┐                           │
│    ↓            ↓                           │
│  [verify]   [dr-smoke]                      │
│    Secrets   Test GCP/Docker                │
│    ↓            ↓                           │
│    └─────┬──────┘                           │
│         ↓                                   │
│  [Results posted to Issue #1239]           │
│  [System operational or retry scheduled]   │
│                                             │
│  [security-audit] ← Scheduled (6h)         │
│    Continuous Gitleaks + Trivy scanning    │
│                                             │
└─────────────────────────────────────────────┘
```

---

## 📞 Support & Escalation

| Issue | Contact | Escalation Time |
|-------|---------|-----------------|
| GitHub Actions outage | GitHub Status | Immediate |
| GCP authentication failing | GCP Support | 30 minutes |
| Security audit findings | Security Team | 24 hours |
| Workflow stuck/queued | repo maintainer | 10 minutes |

### Gathering Diagnostic Info

When reporting issues, collect:

```bash
# Workflow logs
gh run view <run-id> --repo kushin77/self-hosted-runner --log > /tmp/workflow-logs.txt

# Commit history
git log --oneline -20 > /tmp/recent-commits.txt

# Secrets status
gh secret list --repo kushin77/self-hosted-runner > /tmp/secrets-list.txt

# Open issues
gh issue list --state open --repo kushin77/self-hosted-runner --limit 10 > /tmp/open-issues.txt
```

---

## 🎓 Learning Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [gh CLI Guide](https://cli.github.com)
- [Workflow Syntax](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions)
- [Repository](https://github.com/kushin77/self-hosted-runner)
- [Deploy Key Remediation Runbook](./DEPLOY_KEY_REMEDIATION_RUNBOOK.md)
- [Phase 6 Completion Issue](https://github.com/kushin77/self-hosted-runner/issues/1266)

---

## 📝 Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2026-03-07 | 1.0 | Initial playbook creation (Phase 6) |

---

**Last Updated**: 2026-03-07  
**Status**: Production Ready  
**Maintainer**: Automation Team

---

## Resilience Loader Rollout — 2026-03-07

- **Status:** Completed — 112/112 workflows patched.
- **Release:** v0.1.1-resilience-2026-03-07
- **Archive:** /tmp/rollout-archive.tgz (attached to release)
- **Tracking issue:** #1254
- **Summary:** All workflow jobs now source the resilience helpers using `source .github/scripts/resilience.sh || true`, providing immutable, ephemeral, idempotent, noop-safe behavior for job setup. Verification artifacts and logs are attached to the release.

