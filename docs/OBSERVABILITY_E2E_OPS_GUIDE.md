# Observability E2E Testing - Ops Setup Guide

**Issue Reference:** [#226](https://github.com/kushin77/self-hosted-runner/issues/226)  
**Workflows:**
- Main test: `.github/workflows/observability-e2e.yml`
- Secret validator: `.github/workflows/secret-validator-observability.yml`

---

## Quick Start for Ops

### What You Need to Do

Add two repository secrets to GitHub:

1. **`SLACK_WEBHOOK_URL`** — Incoming webhook URL from Slack (starts with `https://hooks.slack.com/services`)
2. **`PAGERDUTY_SERVICE_KEY`** — Integration key from PagerDuty

Once added, the observability E2E workflow is ready to validate end-to-end notification delivery.

### Security Requirements

- 🔒 **Never store secrets in Git** — Use GitHub's encrypted secret management
- 🔒 **Do not paste secrets in Draft issues/issues** — Secrets are sensitive
- 🔒 **Use organization-level secrets if available** — Scoped to this repository only
- 🔒 **Rotate periodically** — Recommend quarterly rotation

---

## Step-by-Step: Add Secrets to GitHub

### Prerequisites

You must have:
- GitHub repository write access (Organization Owner or Admin)
- Valid Slack and PagerDuty accounts with admin permissions
- Ability to create incoming webhooks/integrations in both platforms

### Part 1: Add SLACK_WEBHOOK_URL

#### 1.1 Obtain Slack Webhook URL

1. Go to https://api.slack.com/apps
   - Log in with your Slack workspace admin credentials
   
2. Create a new Slack app:
   - Click **"Create New App"**
   - Select **"From scratch"**
   - App Name: `GitHub Observability Alerts` (or similar)
   - Workspace: Select your Slack workspace
   - Click **"Create App"**

3. Navigate to **Incoming Webhooks**:
   - Left sidebar → **"Incoming Webhooks"**
   - Toggle: **"Activate Incoming Webhooks"** → ON

4. Add a new webhook to your workspace:
   - Click **"Add New Webhook to Workspace"**
   - Select channel: Choose `#devops`, `#alerts`, or similar (recommended: dedicated alert channel)
   - Click **"Allow"**

5. Copy the webhook URL:
   - You'll see a long URL starting with `https://hooks.slack.com/services/T.../B.../...`
   - **Copy this URL** (you'll need it in GitHub)

#### 1.2 Add to GitHub Secrets

1. Go to GitHub repo: **Settings** → **Secrets and variables** → **Actions**
   
2. Click **"New repository secret"**

3. Fill in:
   - **Name:** `SLACK_WEBHOOK_URL` (exactly as shown)
   - **Value:** Paste the webhook URL from Slack
   
4. Click **"Add Secret"** → Done ✓

### Part 2: Add PAGERDUTY_SERVICE_KEY

#### 2.1 Obtain PagerDuty Integration Key

1. Go to https://www.pagerduty.com and log in as admin

2. Navigate to **Services**:
   - Top menu → **"Services"** → **"Service Directory"**

3. Create or select a service:
   - To create: Click **"+ New Service"**
     - Name: `GitHub Observability`
     - Escalation Policy: Select your team's escalation policy
     - Click through remaining fields and **Save**
   - To use existing: Click on a service that should receive GitHub alerts

4. Add Prometheus integration:
   - In the service details, go to **"Integrations"**
   - Click **"+ Add Integration"** or **"New Integration"**
   - Search for: **"Prometheus"** or **"Alertmanager"**
   - Select the Prometheus integration type
   - Click **"Add Integration"**

5. Copy the integration key:
   - You'll see an **Integration Key** (example: `aE123bcD4ef5Gh6ijKLm789No`)
   - **Copy this key**

#### 2.2 Add to GitHub Secrets

1. Go to GitHub repo: **Settings** → **Secrets and variables** → **Actions**

2. Click **"New repository secret"**

3. Fill in:
   - **Name:** `PAGERDUTY_SERVICE_KEY` (exactly as shown)
   - **Value:** Paste the integration key from PagerDuty
   
4. Click **"Add Secret"** → Done ✓

---

## Verify Setup

### Quick Check in GitHub

```bash
# You can verify secrets were added (command-line)
gh secret list -R kushin77/self-hosted-runner | grep -E "SLACK|PAGERDUTY"
```

### Run E2E Test in GitHub Actions

1. Go to **Actions** tab in GitHub

2. Select **"Observability E2E Test"** workflow

3. Click **"Run workflow"**
   - **test_real:** Select `true` (to test real endpoints)
   - **test_type:** Select `all` (to test both Slack and PagerDuty)
   - **debug_mode:** `false` (or `true` for verbose output)

4. Click **"Run workflow"** button

5. Monitor execution:
   - Watch job logs in real-time
   - Look for job: **"Check Secret Availability"** to confirm secrets detected
   - Look for: **"Run real endpoint test (Slack)"** and **"Run real endpoint test (PagerDuty)"**

6. Verify notifications received:
   - Check your Slack channel for test alert
   - Check PagerDuty for triggered incident

---

## Expected Workflow Behavior

### With Secrets Configured

**Default behavior (manual trigger):**
- Mock E2E test always runs ✓ (validates local setup)
- Real E2E test runs if `test_real=true` input is set

**With test_real=true:**
- Slack notification sent to webhook URL
- PagerDuty incident created via integration key
- Both services log activity

**Scheduled run (if enabled):**
- Cron schedule: `0 2 * * 1` (Monday 2 AM UTC)
- Runs mock test automatically
- Real tests skipped on schedule (manual trigger only)

### Without Secrets

**Workflow still runs:**
- Mock tests execute successfully ✓
- Real tests are skipped
- Guide displayed in job: **"Display Secret Setup Guide"**
- Validation job reports missing secrets

### Idempotent & Ephemeral

Each run:
- ✓ Creates temporary Docker network
- ✓ Spins up mock webhook receiver
- ✓ Generates alertmanager config from template
- ✓ Cleans up all resources after completion
- ✓ Safe to re-run multiple times

---

## Troubleshooting

### Issue: GitHub Actions reports secrets not found

**Solution:**
1. Verify secret names are **exactly**:
   - `SLACK_WEBHOOK_URL` (not `SLACK_URL` or `SLACK_WEBHOOK`)
   - `PAGERDUTY_SERVICE_KEY` (not `PAGERDUTY_KEY`)
2. Check in GitHub: **Settings** → **Secrets and variables** → **Actions**
3. Re-run workflow after adding

### Issue: Slack test runs but no message appears

**Troubleshooting:**
1. Verify webhook URL is correct: Try sending test via Slack UI first
   - Settings → Manage Apps → Custom Integrations → Incoming Webhooks
   - Select webhook → "Test Message"
2. Check webhook channel still exists and bot has post permissions
3. Verify URL hasn't expired (regenerate if needed)
4. Check GitHub Actions logs for HTTP error codes

### Issue: PagerDuty test runs but no incident created

**Troubleshooting:**
1. Verify integration key format (example: `aE123bcD4ef5Gh6ijKLm789No`)
2. Check service is enabled and not in maintenance window
3. Verify escalation policy is configured
4. Test integration key via PagerDuty UI: **Services** → **Integrations** → **Test Integration**
5. Check for rate limiting (PagerDuty may throttle rapid requests)

### Issue: Timeout or connection errors

**If real tests timeout:**
1. Check network connectivity: Runner must reach Slack/PagerDuty APIs
2. Verify firewall allows outbound HTTPS (port 443)
3. Check for DNS resolution issues
4. PagerDuty: Rate limiting may apply (wait 30s and retry)

**If mock tests timeout:**
1. Check Docker availability on runner
2. Ensure sufficient disk space for container images
3. Check Docker daemon logs

### Issue: Need to rotate credentials

**For Slack:**
1. Go to Slack API: https://api.slack.com/apps
2. Select app → Incoming Webhooks
3. Click settings icon next to webhook
4. Regenerate URL
5. Update `SLACK_WEBHOOK_URL` secret in GitHub with new URL

**For PagerDuty:**
1. Go to PagerDuty: Services → Service → Integrations
2. Click settings icon next to Prometheus integration
3. Regenerate integration key
4. Update `PAGERDUTY_SERVICE_KEY` secret in GitHub with new key

---

## Scheduling & Automation

### Current Configuration

- **Trigger:** Manual dispatch (`workflow_dispatch`)
- **Cron:** Commented out (Monday 2 AM UTC)

### Enable Scheduled Runs

To run tests automatically on a schedule:

1. Edit `.github/workflows/observability-e2e.yml`

2. Uncomment the schedule section:
   ```yaml
   schedule:
     - cron: '0 2 * * 1'  # Monday 2 AM UTC
   ```

3. Adjust timing as needed (Format: `minute hour day month day-of-week`)
   - Examples:
     - `0 2 * * 1` = Monday 2 AM UTC
     - `0 9 * * *` = Daily 9 AM UTC
     - `0 */6 * * *` = Every 6 hours

4. Commit change

### Benefits of Scheduled Runs

✓ Automatic validation of alert pipeline  
✓ Early detection of webhook/integration failures  
✓ Confidence in on-call alerting before incidents  
✓ Historical trend of alert delivery success  

---

## Configuration Details

### Script Locations

| Script | Purpose |
|--------|---------|
| `scripts/automation/pmo/prometheus/generate-alertmanager-config.sh` | Generates `alertmanager.yml` from template with Slack/PagerDuty URLs |
| `scripts/automation/pmo/prometheus/run_e2e_ephemeral_test.sh` | Starts mock webhook, Alertmanager, and validates alert delivery |
| `scripts/automation/pmo/prometheus/alertmanager.yml.tpl` | Template for Alertmanager config with placeholder URLs |

### Environment Variables Used

| Variable | Source | Used By |
|----------|--------|---------|
| `SLACK_WEBHOOK_URL` | Repository Secret | `generate-alertmanager-config.sh` → Alertmanager config |
| `PAGERDUTY_SERVICE_KEY` | Repository Secret | `generate-alertmanager-config.sh` → Alertmanager config |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Workflow default | Optional OTEL integration |

---

## References

### External Documentation

- **Slack Incoming Webhooks:** https://api.slack.com/messaging/webhooks
- **PagerDuty Prometheus Integration:** https://developer.pagerduty.com/docs/
- **Prometheus Alertmanager:** https://prometheus.io/docs/alerting/latest/configuration/
- **GitHub Actions Secrets:** https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions

### Internal References

- Related Issue: **#226** (Ops: Add SLACK_WEBHOOK_URL and PAGERDUTY_SERVICE_KEY)
- Workflow: `.github/workflows/observability-e2e.yml`
- Validator: `.github/workflows/secret-validator-observability.yml`

---

## Support

For issues or questions:

1. **Check workflow logs:** GitHub Actions job output
2. **Review this guide:** Look for specific issue section above
3. **Test credentials:** Verify in Slack/PagerDuty UI first
4. **Enable debug mode:** Re-run workflow with `debug_mode=true`

---

**Last Updated:** March 7, 2026  
**Maintained By:** DevOps/Platform Team
