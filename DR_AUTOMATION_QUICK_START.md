# DR Automation - Quick Start for Admin

## Current Status
🔴 **Waiting for**: GCP service account JSON to be uploaded to GitHub Secret

## What to Do Now

### 1. Get the Service Account JSON File

Contact your DevOps team or check your local credentials for a file like:
```
service-account.json
gcp-sa-key.json
credentials.json
```

### 2. Validate It Locally

```bash
jq -e . /path/to/service-account.json
```

If it prints the JSON and exits with code 0, you're good.

### 3. Upload to GitHub (Pick ONE Method)

**Easiest Method (Recommended):**
```bash
gh secret set GCP_SERVICE_ACCOUNT_KEY \
  --repo kushin77/self-hosted-runner \
  --body-file /path/to/service-account.json
```

**If gh CLI not installed:**
1. Go to: https://github.com/kushin77/self-hosted-runner/settings/secrets/actions
2. Click "New repository secret"
3. Name: `GCP_SERVICE_ACCOUNT_KEY`
4. Value: Copy-paste contents of your service-account.json file
5. Click "Add secret"

### 4. Verify Upload

```bash
gh secret list --repo kushin77/self-hosted-runner | grep GCP
```

Should show:
```
GCP_PROJECT_ID              less than a minute ago
GCP_SERVICE_ACCOUNT_KEY     just now
```

## What Happens Automatically

✅ **~5 minutes later**: System detects valid secret
✅ **~10 minutes later**: Live DR test starts automatically
✅ **~40-45 minutes later**: Test completes and issue #925 closes automatically

No further action needed from you!

## Monitoring Your Automation

### Check Secret Status
```bash
gh secret list --repo kushin77/self-hosted-runner
```

### Check Monitor Workflow
```bash
gh run list --workflow dr-secret-monitor-and-trigger.yml \
  --repo kushin77/self-hosted-runner \
  --limit 3
```

### Check DR Workflow Results
```bash
gh run list --workflow docker-hub-weekly-dr-testing.yml \
  --repo kushin77/self-hosted-runner \
  --limit 3
```

### Watch Issue #925 Close
https://github.com/kushin77/self-hosted-runner/issues/925

## Troubleshooting

### "Secret upload failed"
- Make sure you're using the correct repo: `kushin77/self-hosted-runner`
- Check your GitHub credentials: `gh auth status`

### "Monitor workflow not detecting secret"
- Wait 5-10 minutes (it runs every 5 minutes)
- Manually check: `gh secret list --repo kushin77/self-hosted-runner | grep GCP_SERVICE_ACCOUNT_KEY`

### "DR test still failing"
- Run the monitor workflow manually: `gh workflow run dr-secret-monitor-and-trigger.yml --repo kushin77/self-hosted-runner`
- Check DR workflow logs: `gh run list--workflow docker-hub-weekly-dr-testing.yml --repo kushin77/self-hosted-runner --limit 1`

### "Need to force a re-run"
```bash
# Manually trigger the monitor
gh workflow run dr-secret-monitor-and-trigger.yml \
  --repo kushin77/self-hosted-runner \
  -f force_run=true

# Or manually trigger the DR test
gh workflow run docker-hub-weekly-dr-testing.yml \
  --repo kushin77/self-hosted-runner \
  -f dry_run=false \
  -f verbose=true
```

---

**That's it!** The rest happens automatically. Once you upload the secret, you can sit back and watch it all work.
