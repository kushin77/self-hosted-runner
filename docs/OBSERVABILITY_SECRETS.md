# Observability: Secrets and E2E guide

This document explains where to add repository secrets required for real end-to-end validation of the Observability stack and how to run the Observability E2E workflow.

## Required secrets
- `SLACK_WEBHOOK_URL` — Slack incoming webhook URL (https://hooks.slack.com/services/...).
- `PAGERDUTY_SERVICE_KEY` — PagerDuty integration/service key.

Add these as **Repository** secrets in: Settings → Secrets and variables → Actions. Do NOT paste secrets into issues or Draft issues.

## How to run the E2E workflow (manual)
1. Confirm secrets have been added to this repo (see above).
2. Go to Actions → Observability E2E → Run workflow.
3. Set `test_real=true` and start the run.
4. Review uploaded artifact `observability-e2e-logs` after the run completes.

## Scheduled validation
A scheduled run may be configured to run nightly to ensure routing and receivers remain functional. The scheduled workflow runs a mock test by default; when `test_real=true` it validates against the real receivers and should only be used when secrets are present.

## Security notes
- Prefer org-level secrets scoped to this repo if available.
- Rotate keys and webhooks periodically and on any incident.
- If you prefer not to store PagerDuty keys as secrets, consider using short-lived service tokens or a Vault-backed approach and updating `generate-alertmanager-config.sh` to fetch secrets securely at runtime.
