# Observability Workflows Registry

Complete index and operational guide for all observability CI/CD workflows in this repository.

**Last Updated:** March 7, 2026  
**Status:** Production-Ready

---

## Quick Links

| Workflow | Purpose | Schedule | Trigger | Status |
|----------|---------|----------|---------|--------|
| [OTEL Collector Test](#otel-collector-test) | Local OTLP exporter validation | On push/PR | `deploy/otel/**` | ✅ |
| [Observability E2E](#observability-e2e-test) | End-to-end observability pipeline test | Daily 02:00 UTC | Manual + cron | ✅ |
| [Secret Validator](#secret-validator) | Detect missing observability secrets | Daily 00:00 UTC | Schedule | ✅ |
| [Observability Monitor](#observability-monitor) | Failure alerting & auto-remediation | On E2E completion | Workflow run | ✅ |

---

## Detailed Workflow Specs

### OTEL Collector Test

**File:** `.github/workflows/ci-otel-collector-test.yml`  
**Issue:** #183

**Purpose:** Validates OTLP exporter functionality in isolation using a local Docker Compose orchestrated Prometheus/OTEL Collector.

**Triggers:**
- Push/PR on changes to `deploy/otel/**`, `services/provisioner-worker/tests/send_otlp.sh`
- Manual dispatch via `workflow_dispatch` (optional debug mode)

**Job:** `otel-collector-test`
- Runs on: `ubuntu-latest`
- Timeout: 15 min
- Continue on error: Yes (non-fatal)

**Steps:**
1. Checkout code
2. Clean up stale OTEL containers (idempotent)
3. Start OTEL Collector with health check (30s polling)
4. Run `send_otlp.sh` test script
5. Validate collector logs for trace/span processing
6. Check for external connectivity issues (non-fatal)
7. Cleanup and summary report

**Success Criteria:**
- Collector container starts and becomes healthy
- OTLP HTTP endpoint responds to test payload
- Collector logs show trace processing

**Failures:**
- Non-fatal (doesn't block downstream jobs)
- Review logs for Docker/network issues
- Check firewall/routing if external services fail

**Metrics:**
- Execution time: ~3-5 min
- Infrastructure: Ephemeral Docker
- Idempotent: Yes (safe to re-run)

---

### Observability E2E Test

**File:** `.github/workflows/observability-e2e.yml`  
**Issue:** #226 (closed)

**Purpose:** Comprehensive end-to-end test for observability pipeline (mock receivers always; real Slack/PagerDuty optional).

**Triggers:**
- Schedule: Daily 02:00 UTC (mock tests)
- Manual dispatch: `workflow_dispatch` with inputs:
  - `test_real=true/false` — enable real endpoint tests
  - `test_type=slack|pagerduty|all` — endpoint filter
  - `debug_mode=true/false` — verbose output

**Jobs:**

1. **secret-check** (outputs `slack_available`, `pagerduty_available`)
   - Detects configured secrets
   - Non-blocking

2. **ephemeral-e2e-test** (matrix: mock, real)
   - Mock test: Always runs, validates local receivers
   - Real test: Only if secrets present + `test_real=true`
   - Jobs: Up to 2 concurrent (mock + real)
   - Timeout: 10 min

3. **secret-guide** (conditional)
   - Displays setup instructions if secrets missing
   - Step-by-step Slack webhook and PagerDuty key retrieval

4. **report**
   - Final execution summary
   - Provides troubleshooting guidance

**Success Criteria:**
- Mock test passes (local Flask webhook receives alert)
- Real tests send notifications to Slack/PagerDuty (if enabled)

**Failures:**
- Mock test failure: Check Alertmanager config, network isolation
- Real test failure: Verify credentials, webhook/integration URLs, rate limiting
- External connectivity: Non-fatal; reported in logs

**Secrets Required (for real tests):**
- `SLACK_WEBHOOK_URL` — Slack incoming webhook
- `PAGERDUTY_SERVICE_KEY` — PagerDuty integration key

**Configuration:**
- Alert template: `scripts/automation/pmo/prometheus/alertmanager.yml.tpl`
- Generator: `scripts/automation/pmo/prometheus/generate-alertmanager-config.sh`
- Test script: `scripts/automation/pmo/prometheus/run_e2e_ephemeral_test.sh`

**Metrics:**
- Execution time: ~5-10 min
- Infrastructure: Docker network + containers (ephemeral)
- Idempotent: Yes

---

### Secret Validator

**File:** `.github/workflows/secret-validator-observability.yml`

**Purpose:** Daily check for missing observability secrets; provides early warning if credentials haven't been configured.

**Triggers:**
- Schedule: Daily 00:00 UTC
- Manual: `workflow_dispatch`
- On changes to validator workflow itself

**Job:** `validate-secrets`
- Runs on: `ubuntu-latest`
- Timeout: 5 min

**Steps:**
1. Check for `SLACK_WEBHOOK_URL` secret
2. Check for `PAGERDUTY_SERVICE_KEY` secret
3. Report missing credentials
4. Provide next steps

**Success Criteria:**
- Both secrets detected (green state)
- Or at least one secret missing (reports missing, non-blocking)

**Output:**
- GitHub Actions logs
- Summary in job output

**Metrics:**
- Execution time: ~30 sec
- No infrastructure
- Idempotent: Yes

---

### Observability Monitor

**File:** `.github/workflows/observability-monitor.yml`  
**Issue:** #1361

**Purpose:** Automated alerting on Observability E2E failures; creates GitHub issues, notifies Slack/PagerDuty, auto-closes on recovery.

**Triggers:**
- `workflow_run` on "Observability E2E Test" completion

**Job:** `handle-run`
- Runs on: `ubuntu-latest`
- Timeout: 5 min

**Conditional Steps:**

**On Failure:**
1. Create GitHub issue (or append comment to existing) with:
   - Title: "Alert: Observability E2E failed"
   - Body: Run URL + conclusion reason
   - Labels: `observability`, `e2e-failure`
   - Assignee: `${{ ALERT_ASSIGNEE }}` (if configured)
2. Notify Slack (if `SLACK_WEBHOOK_URL` secret present)
3. Trigger PagerDuty event (if `PAGERDUTY_SERVICE_KEY` secret present)

**On Success:**
1. Find open alert issue with title "Alert: Observability E2E failed"
2. Append comment: "Observability E2E succeeded on a subsequent run — closing alert automatically."
3. Close issue

**Secrets (optional):**
- `SLACK_WEBHOOK_URL` — For Slack notifications
- `PAGERDUTY_SERVICE_KEY` — For PagerDuty event API
- `ALERT_ASSIGNEE` — GitHub username to auto-assign

**Metrics:**
- Execution time: ~1-2 min
- No infrastructure
- Idempotent: Yes (reuses issue title)

---

## Operational Runbook

### Scenario 1: Secret Validator Reports Missing Secrets

**Indicator:** Daily validator workflow output shows missing `SLACK_WEBHOOK_URL` or `PAGERDUTY_SERVICE_KEY`.

**Steps:**
1. Go to GitHub repo → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Follow guide in `.github/workflows/observability-e2e.yml` (job: `secret-guide`)
4. Add credentials:
   - **Slack:** https://api.slack.com/apps → Create App → Incoming Webhooks → Add to Workspace
   - **PagerDuty:** https://www.pagerduty.com → Services → Service → Add Integration → Prometheus
5. Manually trigger `.github/workflows/observability-e2e.yml` with `test_real=true` to verify

**Expected Outcome:** Slack/PagerDuty receive test notifications within 1 min.

---

### Scenario 2: OTEL Collector Test Fails

**Indicator:** CI fails for PR touching `deploy/otel/**` or `send_otlp.sh`.

**Steps:**
1. Open failed workflow run in GitHub Actions
2. Check logs:
   - **Start failure:** Docker Compose not available; check runner environment
   - **Health check timeout:** Collector not starting; check Docker daemon logs
   - **Test failure:** Check OTLP endpoint accessibility; verify curl connectivity
   - **Log validation failure:** Collector didn't process spans; check template config
3. For local debugging:
   ```bash
   cd deploy/otel
   docker compose up -d
   sleep 5
   cd ../../services/provisioner-worker/tests
   chmod +x send_otlp.sh
   ./send_otlp.sh
   cd ../../../deploy/otel
   docker compose logs otel-collector
   docker compose down
   ```

**Expected Outcome:** Collector logs contain `ResourceSpans` or `span` data.

---

### Scenario 3: Observability E2E Test Fails (Real Endpoints)

**Indicator:** Manual run with `test_real=true` completes; workflow or monitor reports failure.

**Steps:**
1. Check job `Check Secret Availability` for secret detection
2. Review job logs for:
   - **Mock test failure:** Contact DNS/network team; check test script syntax
   - **Real Slack failure:** Verify webhook URL format; test in Slack UI first
   - **Real PagerDuty failure:** Verify integration key; check service is enabled and not in maintenance
3. If connectivity error: Check firewall allows outbound HTTPS to Slack/PagerDuty APIs
4. If rate limit: Wait and retry; PagerDuty may throttle rapid events

**Expected Outcome:** Subsequent manual run or next scheduled run succeeds and auto-closes alert.

---

### Scenario 4: Monitor Creates Alert Issue

**Indicator:** GitHub issue "Alert: Observability E2E failed" appears; Slack/PagerDuty notifications received.

**Steps:**
1. Review issue for run URL and failure conclusion
2. Click run URL to open Actions job output
3. Investigate logs using Scenarios 1-3 above
4. Fix underlying issue (may be secrets, connectivity, or flaky test)
5. Manually trigger Observability E2E workflow again
6. Monitor will auto-close alert when next successful run completes

**Expected Outcome:** Alert issue closed automatically within 24 hours (next scheduled run).

---

### Scenario 5: Configure Auto-Assignee

**Indicator:** Ops wants alerts assigned to on-call user.

**Steps:**
1. Decide on GitHub username (e.g., `on-call-team` or specific user)
2. Add repository secret:
   - Name: `ALERT_ASSIGNEE`
   - Value: GitHub username
3. Next alert will be assigned automatically

**Expected Outcome:** New alert issues assigned to specified user.

---

## Troubleshooting Matrix

| Symptom | Likely Cause | Resolution |
|---------|--------------|-----------|
| OTEL Collector won't start | Docker daemon unavailable | Check runner Docker socket; restart daemon if needed |
| Health check times out | Collector slow to start | Increase polling timeout in workflow (edit `observability-e2e.yml`) |
| Slack test succeeds, real fails | Webhook URL format invalid | Test webhook manually in Slack UI; regenerate if needed |
| PagerDuty events not creating incidents | Service in maintenance window | Check PagerDuty service status; verify escalation policy |
| Monitor gets stuck creating alerts | Duplicate issue title race | (Rare) Manually close old alert, next run creates fresh one |
| Secrets not detected by validator | Wrong secret names | Verify names in Settings: `SLACK_WEBHOOK_URL`, `PAGERDUTY_SERVICE_KEY` exactly |

---

## Configuration Reference

### Required Environment Variables (for tests to run)

For E2E real-endpoint tests only:

```bash
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T.../B.../...
PAGERDUTY_SERVICE_KEY=aE123bcD4ef5...
```

### Optional Automation Variables

```bash
ALERT_ASSIGNEE=username  # For auto-assigning alerts
```

### Workflow Cron Schedules

```yaml
# Secret Validator: Daily at midnight UTC
- cron: '0 0 * * *'

# Observability E2E: Daily at 2 AM UTC (off-peak)
- cron: '0 2 * * *'
```

---

## Related Documentation

- [OBSERVABILITY_E2E_OPS_GUIDE.md](./OBSERVABILITY_E2E_OPS_GUIDE.md) — Step-by-step secret setup
- [IMMUTABLE_EPHEMERAL_IDEMPOTENT.md](./IMMUTABLE_EPHEMERAL_IDEMPOTENT.md) — Design principles
- [.github/workflows/ci-otel-collector-test.yml](../.github/workflows/ci-otel-collector-test.yml) — OTEL workflow
- [.github/workflows/observability-e2e.yml](../.github/workflows/observability-e2e.yml) — E2E workflow
- [.github/workflows/secret-validator-observability.yml](../.github/workflows/secret-validator-observability.yml) — Validator
- [.github/workflows/observability-monitor.yml](../.github/workflows/observability-monitor.yml) — Monitor
- GitHub Issues: #183, #226, #1358, #1361

---

## Support & Escalation

**For Questions:**
- Review this registry and troubleshooting matrix first
- Check GitHub Actions job logs for detailed error messages
- Open an issue with `observability` label

**For Production Incidents:**
1. Check if Observability E2E monitor has filed an alert
2. Follow Scenario 3-4 in the runbook above
3. Page on-call if available (via PagerDuty integration)

**For Feature Requests:**
- Note desired capability in an issue
- Platform team will prioritize

---

**Maintained by:** Platform Engineering  
**Last Audit:** March 7, 2026
