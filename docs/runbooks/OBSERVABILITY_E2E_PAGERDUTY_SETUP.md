# PagerDuty Integration Setup for Observability E2E

This guide explains how to configure PagerDuty for automated end-to-end delivery verification in the Observability E2E workflows.

## Overview

The Observability E2E automation validates that Alertmanager can:
1. Accept synthetic alerts
2. Route alerts to configured receivers (webhook URLs, integration keys, etc.)
3. Deliver alerts to external services (Slack, PagerDuty, etc.)

When PagerDuty integration is enabled, the test framework will:
- Generate a unique test ID for each alert
- Post the alert to Alertmanager with the test ID embedded
- Poll the PagerDuty REST API to confirm an incident was created
- Report success or failure based on API response

## Prerequisites

- **PagerDuty account** with API access
- **PagerDuty Service** (where Alertmanager will send events)
- **PagerDuty API Token** (for querying incidents)
- **GitHub Secrets** configured in your repository

## Setup Steps

### 1. Obtain PagerDuty Service Key

Navigate to your PagerDuty service:
1. Go to **Services** → Select your Alertmanager integration service
2. Copy the **Integration Key** (this is your service key)

### 2. Generate PagerDuty REST API Token

1. In PagerDuty, go to **User Settings** or **Team Settings** → **API Access**
2. Click **Generate API Token**
3. Create a token with scope:
   - **Read** access to Incidents (to query for test events)
   - Token name: `alertmanager-e2e-verify` (recommended)
4. Copy the token value

⚠️ **Keep this token secure** — do not commit it to source control.

### 3. Add GitHub Secrets

Add two secrets to your GitHub repository:

| Secret Name | Value | Purpose |
|---|---|---|
| `PAGERDUTY_SERVICE_KEY` | Integration key from step 1 | Tells Alertmanager where to send events |
| `PAGERDUTY_API_TOKEN` | API token from step 2 | Allows test script to query incidents API for verification |

Steps:
1. Go to your GitHub repo **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add `PAGERDUTY_SERVICE_KEY` and `PAGERDUTY_API_TOKEN`

### 4. Verify Configuration

Run a manual test:

```bash
gh workflow run observability-e2e-dispatch.yml \
  --repo <owner>/<repo> \
  -f test_type=pagerduty \
  -f debug_mode=true
```

Monitor the workflow logs:
- Script should report `PAGERDUTY key length after read: <N>` (non-zero)
- Script should poll PagerDuty API ~12 times over 60 seconds
- Expect either ✓ **PagerDuty incident found** or ⚠ **verification failed**

## How the Test Works

### Alert Payload Structure

Each test alert includes:
- `alertname`: `TestAlert`
- `severity`: `critical`
- `test_id`: Unique identifier (e.g., `e2e-1709869500123456789-12345`)
- `summary`: `E2E test alert`

### Verification Flow

```
1. Script generates unique test_id
2. Alertmanager receives alert with test_id in annotations
3. Alert routed to PagerDuty service key
4. PagerDuty creates incident from webhook event
5. Script polls PagerDuty REST API (Incidents endpoint)
6. Script searches incident list for test_id match
7. Report success/failure
```

### Polling Details

- **Polling window**: 60 seconds
- **Polling interval**: 5 seconds
- **Max retries**: 12 attempts
- **Query**: Incidents created in last 2 minutes (since alert time)

## Workflow Triggers

PagerDuty verification runs in:

1. **Manual Dispatch** (`.github/workflows/observability-e2e-dispatch.yml`)
   - Trigger: Manual workflow dispatch with `test_type=pagerduty` or `test_type=all`
   - Requires both secrets present

2. **Scheduled Nightly** (`.github/workflows/observability-e2e-schedule.yml`)
   - Trigger: Daily at 02:00 UTC
   - Automatically skips if secrets are not configured
   - Both tests (Slack + PagerDuty) run if all secrets available

3. **CI Integration** (`.github/workflows/observability-e2e-mock-test.yml`)
   - Trigger: Push to `main`, pull requests on `main`
   - Uses internal mock webhook (no external dependencies)
   - No PagerDuty verification (fast feedback)

## Troubleshooting

### "PagerDuty verification failed: no incident found"

**Possible causes:**
1. Service key is invalid or not linked to Alertmanager integration in PagerDuty
2. Alertmanager is not configured to use the PagerDuty receiver
3. PagerDuty integration is in "disabled" or "maintenance" state
4. Event routing rules or escalation policies not configured

**Steps to debug:**
- Manually trigger a test alert in PagerDuty UI
- Check PagerDuty integration settings (ensure `Events v2` or `Events` API is enabled)
- Review Alertmanager logs in workflow output for errors
- Verify incident list in PagerDuty web UI for recent test events

### "ERROR: PAGERDUTY key is empty after read"

**Cause:** Secret not properly set or GitHub Actions secret injection failed

**Fix:**
- Verify secrets are configured in repo settings
- Re-try the workflow run
- Check if secrets were accidentally deleted or rotated

### API Token Errors (401, 403)

**Possible causes:**
1. Token is expired or revoked
2. Token does not have "Read" permission for Incidents
3. Token is formatted incorrectly (extra spaces, etc.)

**Fix:**
- Generate a new token in PagerDuty
- Verify token has `incidents.read` scope
- Update the GitHub secret with new token value

## Best Practices

✅ **Do:**
- Rotate `PAGERDUTY_API_TOKEN` quarterly
- Use a dedicated PagerDuty user/service account for automation tokens
- Keep incident query window narrow (current: 2 minutes) to avoid noise
- Monitor scheduled E2E runs for failures
- Document test results for audit/compliance

❌ **Don't:**
- Share tokens in Slack, pull requests, or logs
- Use personal user tokens for automation
- Store tokens in environment files or `.env` files
- Modify PagerDuty events/incidents during test runs (may interfere with verification)

## Advanced Configuration

### Custom Polling Window

To adjust polling time (default: 60s), edit the script:

```bash
# In run_e2e_ephemeral_test.sh, change:
for i in $(seq 1 12); do  # 12 iterations × 5s = 60s
  sleep 5
done
```

### Deduplication Keys

For advanced setups, add dedup keys to Alertmanager config to group alerts:

```yaml
pagerduty_configs:
  - service_key: '<key>'
    dedup_key: 'alertmanager-{{ .Alerts.GroupLabels.alertname }}'
```

### Incident State Verification

To verify incident state (not just existence), extend the polling script to check `status` field.

## Support & Questions

For issues or questions about this integration:
1. Check the troubleshooting section above
2. Review workflow logs (click run in GitHub Actions)
3. Open an issue: [Observability E2E Automation Issues](https://github.com/kushin77/self-hosted-runner/issues?q=observability+e2e)

---

**Last Updated:** March 8, 2026  
**Version:** 1.0  
**Status:** Stable

