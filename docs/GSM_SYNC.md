# GCP Secret Manager (GSM) → GitHub Actions Secrets sync

This document describes the recommended, secure procedure to sync secrets stored in Google Cloud Secret Manager (GSM) into GitHub Actions repository secrets for use by the Observability E2E automation.

Prerequisites
- `gcloud` authenticated with a principal that has `roles/secretmanager.secretAccessor` on the target project
- `gh` CLI authenticated with a token that has `repo` scope (to write repo secrets)

Quick usage (local operator):

```bash
./scripts/ops/gsm_sync.sh --project your-gcp-project --repo kushin77/self-hosted-runner \
  SLACK_WEBHOOK_URL PAGERDUTY_SERVICE_KEY PAGERDUTY_API_TOKEN
```

Security Notes
- Avoid committing sensitive values. This tool reads from GSM and writes directly to GitHub secrets via `gh secret set` using a temporary file.
- Prefer using Workload Identity or short-lived credentials for automation runners.
- Limit the `PAGERDUTY_API_TOKEN` to read-only scopes if possible.

Automation
- For fully automated onboarding, ops can run this script from a secure runner with GCP workload identity and a `gh` token stored in the runner environment.

Troubleshooting
- If a secret is missing in GSM, the script will log a warning and skip it.
- If `gh secret set` fails, ensure the provided `gh` token has `repo` permission and the principal is allowed to write secrets.

### GitHub Actions: run via OIDC

You can run the GSM sync helper from GitHub Actions using Workload Identity Federation. A workflow has been added at `.github/workflows/gsm-sync-run.yml` that runs on `workflow_dispatch`.

Requirements:
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
- The workflow uses `google-github-actions/auth@v1` to obtain an access token via OIDC and `gcloud` to access Secret Manager.

Run options:
- From the GitHub UI: open the Actions tab, select "GSM Sync Run" and click "Run workflow".
- From CLI: `gh workflow run gsm-sync-run.yml --repo kushin77/self-hosted-runner --ref main`

If you prefer, Ops can run the script locally after authenticating with `gcloud`.
