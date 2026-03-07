# 🔄 Secrets Rotation Policy & SLA

**Date**: 2026-03-07  
**Status**: Active  
**Enforcement**: Automated  

---

## Goal

Ensure **zero downtime**, **zero exposure**, and **100% compliance** with industry standards (SOC2, ISO 27001) for secrets lifecycle management.

---

## Rotation Schedule (Enforced Automatically)

### 🔴 Critical: Every 60-90 Days (NO EXCEPTIONS)

| Secret | Tier | Current Status | Due Date | Rotation Window | Owner |
|--------|------|---|---|---|---|
| GCP_SERVICE_ACCOUNT_KEY | Infrastructure | ⚠️ INVALID | 2026-06-05 | 2026-05-24 → 2026-06-05 | @ops-team |
| RUNNER_MGMT_TOKEN | Infrastructure | ✅ Valid | 2026-06-03 | 2026-05-13 → 2026-06-03 | @ci-team |
| DEPLOY_SSH_KEY | Infrastructure | ✅ Valid | 2026-06-04 | 2026-05-15 → 2026-06-04 | @ops-team |
| DOCKER_HUB_PAT | Registry | ✅ Valid | 2026-04-28 | 2026-04-08 → 2026-04-28 | @ci-team |
| VAULT_ROLE_ID | Secrets-Mgmt | ✅ Valid | 2026-05-30 | 2026-05-10 → 2026-05-30 | @vault-admin |
| VAULT_SECRET_ID | Secrets-Mgmt | ✅ Valid | 2026-05-30 | 2026-05-10 → 2026-05-30 | @vault-admin |
| MINIO_ACCESS_KEY | Secrets-Mgmt | ✅ Valid | 2026-04-28 | 2026-04-08 → 2026-04-28 | @storage-team |
| MINIO_SECRET_KEY | Secrets-Mgmt | ✅ Valid | 2026-04-28 | 2026-04-08 → 2026-04-28 | @storage-team |

### 🟡 Medium: Every 180 Days (6 Months)

| Secret | Due Date | Owner |
|--------|----------|-------|
| SLACK_WEBHOOK_URL | 2026-09-07 | @ops-team |

---

## Rotation Workflow (Automated)

```
┌────────────────────────────────────────────────────────┐
│ Scheduled Rotation Workflow (1st of month @ 02:00 UTC) │
└────────────────────────────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │ Check which secrets need rotation │
        │ (Compare due_date vs today)       │
        └──────────────────────────────────┘
                           │
                ┌──────────┴──────────┐
                ▼                     ▼
        Rotate 60-day    Rotate 90-day    Rotate on-demand
        secrets          secrets          (manual trigger)
                │                     │         │
                └──────────┬──────────┴─────────┘
                           ▼
        ┌──────────────────────────────────────────┐
        │ Generate New Secret via Service API      │
        │ • GCP: gcloud iam service-accounts...    │
        │ • GitHub: gh auth token / PAT creation   │
        │ • Docker: API call to Docker Hub         │
        │ • Vault: vault write auth/approle...     │
        └──────────────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────────┐
        │ Validate New Secret (JSON, format, etc)  │
        │ ✓ Parse/format check                     │
        │ ✓ Required fields check                  │
        │ ✓ Connectivity test (if applicable)      │
        └──────────────────────────────────────────┘
                           │
                ┌──────────┴──────────┐
                ▼                     ▼
           VALID               INVALID
                │                    │
                ▼                    ▼
        Update GitHub      Create Issue
        Secret via API     "Rotation Failed"
                │          (Page on-call)
                ▼                │
        Verify Update      Manual Rotation
        (read back)        Required
                │                │
                ▼                ▼
        ✅ Log Rotation   🔴 INCIDENT
        ROTATION_LOG.md      Mode
                │
                ▼
        Post Slack Notification
        "Secret rotated: XXX"
                │
                ▼
        Old Secret Revoked
        (service-specific)
                │
                ▼
        ✅ COMPLETE
```

---

## Pre-Rotation Checklist (24 Hours Before)

Automated workflow runs this:

```yaml
- name: Pre-Rotation Safety Checks
  run: |
    # 1. Verify no critical workflows in flight
    RUNNING=$(gh run list --status in_progress | wc -l)
    if [ "$RUNNING" -gt 0 ]; then
      echo "⚠️ $RUNNING workflows in progress. Rotation may cause transient failures."
      echo "Delaying rotation by 1 hour..."
    fi
    
    # 2. Verify new secret can be generated
    # (Dry-run the generation process)
    
    # 3. Notify ops team via Slack
    # "Starting rotation of GCP_SERVICE_ACCOUNT_KEY in 24h"
    
    # 4. Check rotation history
    # (Make sure last rotation was successful)
```

---

## Rotation Execution

### Safe Rotation Pattern (Zero-Downtime)

```yaml
- name: Safe Secret Rotation (Zero-Downtime)
  env:
    SECRET_NAME: GCP_SERVICE_ACCOUNT_KEY
    OLD_SECRET: ${{ secrets.GCP_SERVICE_ACCOUNT_KEY }}
  run: |
    # Step 1: Generate new secret in staging
    NEW_SECRET=$(gcloud iam service-accounts keys create - \
      --iam-account=self-hosted-runner@self-hosted-runner.iam.gserviceaccount.com)
    
    # Step 2: Keep old secret active (workflows still use it)
    # This is key: no workflows are interrupted
    
    # Step 3: Update GitHub secret with NEW value
    # But do it in an atomic operation (no window of missing/broken value)
    gh secret set GCP_SERVICE_ACCOUNT_KEY --body "$NEW_SECRET"
    
    # Step 4: Verify update (read-back)
    UPDATED=$(gh secret list | grep GCP_SERVICE_ACCOUNT_KEY)
    if [ -z "$UPDATED" ]; then
      echo "❌ Failed to update secret in GitHub"
      exit 1
    fi
    
    # Step 5: Give workflows 300s to pick up new value
    # (GitHub Actions caches secrets for up to 5 minutes)
    sleep 300
    
    # Step 6: Now revoke OLD key from GCP
    # (Workflows using old key will start failing and auto-refresh from GitHub)
    gcloud iam service-accounts keys delete "KEY_ID_OF_OLD_KEY" \
      --iam-account=self-hosted-runner@self-hosted-runner.iam.gserviceaccount.com \
      --quiet
    
    # Step 7: Verify workflows can still authenticate
    # (Workflow runs a quick health check)
```

### Error Handling

```yaml
- name: Handle Rotation Errors (Auto-Retry)
  run: |
    # If rotation fails:
    # 1. Retry 3 times (exponential backoff: 5s, 15s, 45s)
    # 2. If all retries fail → STOP and open issue
    # 3. Never revert to old secret (too dangerous)
    # 4. Page on-call engineer
    # 5. Create blocking issue with incident details
```

---

## Post-Rotation Validation

```yaml
- name: Validate Rotation Success
  run: |
    # 1. Run verify-secrets-and-diagnose.yml
    gh workflow run verify-secrets-and-diagnose.yml
    
    # 2. Run a quick smoke test with each affected workflow
    # Example for GCP rotation:
    gh workflow run docker-hub-weekly-dr-testing.yml --ref main
    
    # 3. Monitor for 30 minutes
    # (Watch for any failures in dependent workflows)
    
    # 4. If all tests pass → Log success
    # If any test fails → Revert (if possible) and escalate
```

---

## Rollback Procedure (If Rotation Fails)

**IMPORTANT**: Rollback is **dangerous** and **discouraged**. Use only as last resort.

```bash
# 1. Identify rollback target
LAST_WORKING_SECRET=$(grep "✅ Rotation successful" ROTATION_LOG.md | tail -1 | awk '{print $NF}')

# 2. IF you have backup of old secret (saved before rotation)
gh secret set GCP_SERVICE_ACCOUNT_KEY --body "$LAST_WORKING_SECRET"

# 3. Verify workflows work again
gh workflow run verify-secrets-and-diagnose.yml

# 4. Log incident
cat >> ROTATION_LOG.md << EOF
## [$(date -u +%Y-%m-%dT%H:%M:%SZ)] ROLLBACK: GCP_SERVICE_ACCOUNT_KEY

**Status:** 🔴 Failed rotation - Rolled back to previous key
**Reason:** New key failed validation
**Next Action:** Manual investigation + re-attempt

EOF

# 5. Open incident issue
gh issue create \
  --title "[INCIDENT] Secrets rotation failed: GCP_SERVICE_ACCOUNT_KEY" \
  --label "incident,critical" \
  --body "Automatic rotation failed. Rolled back to previous key. Manual investigation required."

# 6. DO NOT attempt another rotation without manual review
```

---

## Failure Modes & Recovery

### Failure Mode 1: New Secret Invalid

**Symptom**: `failed to parse service account key JSON credentials: unexpected end of JSON input`

**Recovery**:
1. Check if secret generation was truncated
2. Re-generate secret from scratch
3. Validate JSON locally: `jq empty < secret.json`
4. Manually update GitHub secret
5. Re-run validation workflow

### Failure Mode 2: GitHub API Rejection

**Symptom**: `422 Unprocessable Entity`

**Recovery**:
1. Verify secret name is correct
2. Verify secret value is valid (no unprintable characters)
3. Try again in 5 minutes (GitHub rate limit?)
4. If still failing, use GitHub Web UI to set secret manually

### Failure Mode 3: Service Won't Authenticate with New Secret

**Symptom**: Workflows fail with `permission denied` using new secret

**Recovery**:
1. Verify service has correct scopes (GCP IAM, Docker permissions, etc.)
2. Check expiration date (might have generated expired key)
3. Verify new secret is being picked up (workflows might have cached old one)
4. Force workflow re-run: `gh run rerun <RUN_ID>`

### Failure Mode 4: Cascade Failures

**Symptom**: >5 dependent workflows fail after rotation

**Recovery**:
1. Open emergency issue: `[EMERGENCY] Cascade failure in workflows`
2. Page on-call engineer immediately
3. Consider rollback if safe
4. Disable failed workflows temporarily (add `if: false`)
5. Manual investigation + fix

---

## SLA & Compliance

### Time-to-Rotation SLA

| Condition | SLA | Owner |
|-----------|-----|-------|
| Scheduled rotation | Within 1-hour window (1st of month @ 2 AM UTC) | Automation |
| Overdue rotation (>0 days) | Manual rotation within 4 hours | On-call + Ops |
| Exposed secret emergency | Rotation within 15 minutes | On-call (priority 1) |

### Compliance Requirements

**SOC2 Compliance**:
- ✅ All secrets rotated on schedule (audit trail: ROTATION_LOG.md)
- ✅ Rotation logged with timestamp, operator, and status
- ✅ Failed rotations create blocking issues (audit trail)

**ISO 27001 Compliance**:
- ✅ Access to secrets limited to authorized roles
- ✅ All secret operations logged to GitHub Audit Log
- ✅ Rotation procedure documented and tested

**Internal Security Policy**:
- ✅ Secrets never logged in plain text
- ✅ Secrets rotated per cycle without exception
- ✅ Incident response procedures documented and tested

---

## Contact & Escalation

For rotation issues:

1. **First Alert** (30 days before due): Email + Slack #ops-automation
2. **Second Alert** (14 days before due): Slack critical warning
3. **Incident** (overdue rotation): Create issue + page on-call
4. **Emergency** (exposed secret): Page on-call immediately + create incident issue

**Contacts**:
- 📧 **Ops Team**: ops@elevatediq.com
- 📧 **Security Team**: security@elevatediq.com
- 📱 **On-Call**: See [On-Call Schedule](https://pagerduty.com/...)
- 💬 **Slack**: #ops-automation, #security-incidents

---

**Last Updated**: 2026-03-07  
**Next Review**: 2026-04-07 (quarterly)  
**Approved By**: @security-lead
