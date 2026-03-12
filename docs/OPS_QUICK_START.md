# Ops Quick Start — Provisioning & Runner Registration

This file contains minimal, copy-paste commands for provisioning CI variables, creating labels, and registering a GitLab Runner.

Security: Do not paste tokens into public chat. Run these from a secure terminal.

## A — Provision CI variables & labels (run from repo root)

Set env vars (securely):

```bash
export GITLAB_TOKEN="<YOUR_API_TOKEN>"      # api scope
export CI_PROJECT_ID="<NUMERIC_PROJECT_ID>"
export GITLAB_API_URL="https://gitlab.com/api/v4"

# Run provisioning wrapper (idempotent)
bash scripts/ops/ops_provision_and_verify.sh
```

This runs the helper scripts and prints created labels and variables.

## B — Register GitLab Runner (on runner host)

Set values and run on the host (requires sudo):

```bash
export REGISTRATION_TOKEN="<REGISTRATION_TOKEN_FROM_GITLAB>"
export GITLAB_URL="https://gitlab.com/"
export RUNNER_DESCRIPTION="self-hosted-runner"
export RUNNER_TAGS="automation,primary"

# Download/install and register
bash scripts/ops/register_gitlab_runner_noninteractive.sh
```

## C — Trigger validation and manual triage

From GitLab UI: Project → CI/CD → Pipelines → Run pipeline (branch `main`) → run `validate` and then manually trigger `triage:manual` jobs.

## Troubleshooting
- If API calls fail, verify `GITLAB_TOKEN` has `api` scope and `CI_PROJECT_ID` is correct.
- If runner shows offline, check `sudo systemctl status gitlab-runner` on host.

