# DR Automation: Complete Ops Finalization Checklist

**Date Created:** 2026-03-06  
**Status:** Ready for Ops Execution  
**Total Tasks:** 4 issues + comprehensive runbook  
**Estimated Time:** 30 minutes per issue (2.5 hours total)  

---

## Quick Start for Ops

**You are here because:** The DR automation system is fully implemented and tested. All code is on `main`. To make it fully autonomous, follow these 4 issues in order:

```
Issue 906 (Prerequisites) → Issue 907 (depends on 906) → Issue 908 → Issue 909 (optional, recommended)
```

---

## Issue 906: GitLab API Token Provisioning & Schedule Finalization

**Difficulty:** Easy  
**Time:** 10 minutes  
**Blocker:** Yes (required for 907 & 909)

### Summary
Store GitLab API token in Google Secret Manager and create the quarterly DR dry-run pipeline schedule.

### Steps

1. **Create GitLab API Token:**
   ```bash
   # Option A: Via GitLab Web UI
   # → Project → Settings → Access Tokens → Create Token
   # → Name: "dr-automation"
   # → Scope: "api"
   # → Expiry: 90 days (recommended)
   # → Click "Create"
   ```

2. **Store Token in GSM:**
   ```bash
   export GITLAB_API_TOKEN="glpat-xxxxx..."  # Paste your token
   echo -n "$GITLAB_API_TOKEN" | gcloud secrets versions add gitlab-api-token \
     --data-file=- --project=gcp-eiq
   ```

3. **Verify Storage:**
   ```bash
   gcloud secrets versions access latest --secret=gitlab-api-token --project=gcp-eiq | wc -c
   # Expected: Non-zero character count (e.g., 27)
   ```

4. **Create Quarterly Schedule:**
   ```bash
   cd /path/to/self-hosted-runner  # Your repo root
   export SECRET_PROJECT=gcp-eiq
   export GITLAB_API_URL="https://gitlab.com/api/v4"
   export PROJECT_ID="123456789"  # Your GitLab project ID
   ./scripts/ci/create_dr_schedule.sh
   ```

5. **Verify Schedule Created:**
   ```bash
   # In GitLab UI: Project → CI/CD → Schedules
   # Should see: "DR dry-run quarterly schedule" (runs every 3 months at 03:00 UTC)
   ```

6. **Troubleshooting:**
   - `401 Unauthorized` → Token invalid or missing `api` scope
   - `403 Forbidden` → Token doesn't have project access
   - Schedule already exists → Script will skip (idempotent)

---

## Issue 907: Deploy Key Rotation & Storage

**Difficulty:** Easy  
**Time:** 10 minutes  
**Prerequisite:** Issue 906 ✅  
**Blocker:** Yes (required for GitHub mirror authentication)

### Summary
Generate new SSH deploy key for GitHub mirror, upload public key, and store private key in GitLab CI.

### Steps

1. **Verify Prerequisites:**
   ```bash
   # Check gitlab-api-token exists
   gcloud secrets versions access latest --secret=gitlab-api-token --project=gcp-eiq | wc -c
   # Expected: Non-zero
   ```

2. **Run Rotation Script:**
   ```bash
   cd /path/to/self-hosted-runner
   export SECRET_PROJECT=gcp-eiq
   export GITHUB_REPO="akushnir/self-hosted-runner"  # Your GitHub mirror repo
   export GITLAB_API_URL="https://gitlab.com/api/v4"
   export GROUP_ID="1"  # Or your GitLab GROUP_ID / PROJECT_ID
   ./scripts/ci/rotate_github_deploy_key.sh
   ```

3. **Verify in GitHub:**
   ```bash
   # GitHub Web UI: Settings → Deploy keys
   # Should see: "ci-mirror-2026-03-06T..." (or similar timestamp)
   ```

4. **Verify in GitLab:**
   ```bash
   # GitLab Web UI: Project → Settings → CI/CD → Variables
   # Should see: "GITHUB_MIRROR_SSH_KEY" (Protected, Masked)
   ```

5. **Test Mirror Work:**
   ```bash
   # Run a manual mirror job to confirm authentication works
   # GitLab: CI/CD → Pipelines → (any pipeline) → look for "mirror" job
   ```

6. **Troubleshooting:**
   - `Unauthorized` → gitlab-api-token missing or invalid
   - GitHub SSH key upload fails → Check GitHub PAT has `admin:public_key` scope
   - Old key removal fails → Can ignore (old keys won't interfere)

---

## Issue 908: Backup Integrity Verification

**Difficulty:** Medium  
**Time:** 15 minutes  
**Prerequisite:** Issues 906, 907 (recommended but not required)  
**Blocker:** No (recommended for validation)

### Summary
Upload an encrypted backup sample, verify decryption works, and test archive integrity.

### Steps

1. **Check Existing Backups:**
   ```bash
   export BUCKET=$(gcloud secrets versions access latest --secret=ci-gcs-bucket --project=gcp-eiq)
   gsutil ls -l gs://$BUCKET/backups/ 2>/dev/null | tail -10
   # Expected: At least one .tar.age file (encrypted backup)
   ```

2. **If No Backups Exist Yet:**
   ```bash
   # Option A: Wait for next automated backup from GitLab
   # Option B: Trigger backup manually (see scripts/backup/gitlab_backup_encrypt.sh)
   
   # For manual backup:
   export GITLAB_TOKEN="glpat-xxxxx..."
   ./scripts/backup/gitlab_backup_encrypt.sh --gitlab-url "https://gitlab.com" \
     --gitlab-token "$GITLAB_TOKEN" --bucket "$BUCKET"
   ```

3. **Download Latest Backup:**
   ```bash
   LATEST_BACKUP=$(gsutil ls gs://$BUCKET/backups/*.tar.age 2>/dev/null | tail -1)
   gsutil cp "$LATEST_BACKUP" /tmp/backup-sample.tar.age
   ```

4. **Prepare Decryption Key:**
   ```bash
   # Fetch age private key from GSM (or from secure storage)
   # Key should be at: ~/.age/key.txt (or as specified in setup)
   # If not available, bootstrap from Vault:
   
   export VAULT_ADDR="http://192.168.168.42:8200"
   export VAULT_ROLE_ID=$(gcloud secrets versions access latest --secret=vault-approle-role-id --project=gcp-eiq)
   export VAULT_SECRET_ID=$(gcloud secrets versions access latest --secret=vault-approle-secret-id --project=gcp-eiq)
   
   # Login & fetch age key
   TOKEN=$(curl -sS -X POST $VAULT_ADDR/v1/auth/approle/login \
     -d "{\"role_id\": \"$VAULT_ROLE_ID\", \"secret_id\": \"$VAULT_SECRET_ID\"}" | jq -r '.auth.client_token')
   
   mkdir -p ~/.age
   curl -sS -H "X-Vault-Token: $TOKEN" \
     $VAULT_ADDR/v1/secret/data/dr/age-private-key | jq -r '.data.data.key' > ~/.age/key.txt
   chmod 600 ~/.age/key.txt
   ```

5. **Decrypt & Verify:**
   ```bash
   # Decrypt
   age -d -i ~/.age/key.txt /tmp/backup-sample.tar.age > /tmp/backup.tar
   
   # Verify archive integrity
   tar -tzf /tmp/backup.tar | head -20
   # Expected: Lists GitLab backup objects (e.g., packages.json, projects/, ...)
   
   # Check archive size
   du -h /tmp/backup.tar
   # Expected: Non-zero (typically 100MB - 10GB depending on instance size)
   ```

6. **Document Results:**
   ```bash
   cat > /tmp/backup-integrity-report.txt <<EOF
   Backup Verification Report
   ==========================
   Backup File: $LATEST_BACKUP
   Size: $(du -h /tmp/backup.tar | awk '{print $1}')
   Decryption: ✓ Successful
   Archive Integrity: ✓ Valid (verified with tar -tzf)
   Timestamp: $(date -Iseconds)
   Status: Ready for production restore
   EOF
   
   cat /tmp/backup-integrity-report.txt
   ```

7. **Troubleshooting:**
   - No backups found → Wait for next scheduled backup or trigger manually
   - Decryption fails → Check age private key is correct and accessible
   - Archive corrupted → Backup may be incomplete; check backup logs in GitLab

---

## Issue 909: Monitoring & Alerting Setup (Optional but Recommended)

**Difficulty:** Easy  
**Time:** 10 minutes  
**Prerequisite:** Issues 906, 907, 908 (optional - monitoring works independently)  
**Blocker:** No (recommended for production)

### Summary
Enable Slack alerts and metrics export for the DR pipeline to catch failures immediately.

### Steps

1. **Verify Monitoring Script Exists:**
   ```bash
   ls -la scripts/ci/dr_pipeline_monitor.sh
   # Expected: -rwxr-xr-x (executable)
   ```

2. **Verify CI Template Wired:**
   ```bash
   grep "dr-alert.yml" config/cicd/.gitlab-ci.yml
   # Expected: One line with "ci_templates/dr-alert.yml"
   ```

3. **Verify Slack Webhook:**
   ```bash
   gcloud secrets versions access latest --secret=slack-webhook --project=gcp-eiq | wc -c
   # Expected: Non-zero
   ```

4. **Test Monitoring Locally (Optional):**
   ```bash
   export SECRET_PROJECT=gcp-eiq
   export GITLAB_PROJECT_ID="123456789"  # Your project ID
   ./scripts/ci/dr_pipeline_monitor.sh --poll-interval 5 --timeout 30
   
   # Expected: Script checks pipeline status, posts summary to Slack
   ```

5. **Configure Alert Thresholds (Optional):**
   ```bash
   # Edit: ci_templates/dr-alert.yml
   # Look for RTO_THRESHOLD and RPO_THRESHOLD variables
   # Default: RTO > 60 min, RPO > 30 min
   # Adjust if needed, commit, and push
   ```

6. **Trigger Manual Test:**
   ```bash
   # In GitLab: CI/CD → Schedules → "DR dry-run quarterly schedule" → Play (▶)
   # Watch for Slack notification in your configured channel (default: #dr-automation)
   ```

7. **Verify Alerts:**
   ```bash
   # Check Slack channel for alerts (should appear within 1-2 minutes of pipeline completion)
   # Expected message: "✅ DR pipeline succeeded" or "❌ DR pipeline failed"
   ```

---

## Summary Table

| Issue | Title | Time | Prerequisite | Critical |
|-------|-------|------|--------------|----------|
| 906   | GitLab Token & Schedule | 10 min | None | ✅ Yes |
| 907   | Deploy Key Rotation | 10 min | 906 | ✅ Yes |
| 908   | Backup Verification | 15 min | 906, 907 (rec) | ⚠️ Recommended |
| 909   | Monitoring & Alerts | 10 min | 906, 907, 908 (optional) | ⚠️ Recommended |

**Total time:** ~45 minutes  
**Critical path:** 906 → 907 → (optional 908 & 909)

---

## Final Verification (After All Issues Complete)

```bash
# 1. Confirm all secrets in GSM
gcloud secrets list --project=gcp-eiq --filter="name:gitlab OR name:github OR name:slack OR name:vault"
# Expected: all secrets present

# 2. Confirm quarterly schedule exists in GitLab
# GitLab UI: Project → CI/CD → Schedules → "DR dry-run quarterly schedule"

# 3. Confirm GitHub deploy key exists
# GitHub UI: Settings → Deploy keys → "ci-mirror-..."

# 4. Confirm monitoring is active
# Check GitLab pipeline for dr-alerts job after next scheduled run

# 5. Verify Slack notifications
# Should see messages in #dr-automation channel every quarter
```

---

## Success Criteria

Once all issues are complete, the system is **fully hands-off**:

- ✅ Quarterly DR dry-run scheduled and runs autonomously
- ✅ GitHub mirror updated in real-time
- ✅ Encrypted backups created automatically
- ✅ Slack alerts posted on failures or metric anomalies
- ✅ RTO/RPO metrics exported for trending
- ✅ Zero manual intervention required

**The system is now in steady-state production operation.**

---

## Support & Escalation

- **Questions?** → Read [docs/OPS_FINALIZATION_RUNBOOK.md](docs/OPS_FINALIZATION_RUNBOOK.md)
- **Stuck on an issue?** → Check the troubleshooting section for that issue above
- **Need help?** → Check the reference docs at the bottom of each issue
- **Bug or unexpected behavior?** → Open a GitHub issue or contact the DevOps team

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-06  
**Status:** ✅ Ready for Ops Execution
