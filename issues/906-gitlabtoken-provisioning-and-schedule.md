Title: GitLab API Token Provisioning & Schedule Finalization

Goal: Store GitLab API token in GSM and create the quarterly DR dry-run pipeline schedule using the automated idempotent script.

Status: Ready for Ops

Preconditions:
- A GitLab project or personal access token with `api` scope has been created (see `docs/OPS_FINALIZATION_RUNBOOK.md` Step 1 for guidance).
- The token is ready to store in Google Secret Manager.

Checklist:

- [ ] Create GitLab API token via GitLab web UI (Project → Settings → Access Tokens) or API call. Recommended scope: `api`. Recommended expiry: 90 days.
- [ ] Run the token storage command:
  ```bash
  GITLAB_API_TOKEN="<YOUR_TOKEN>" 
  echo -n "$GITLAB_API_TOKEN" | gcloud secrets versions add gitlab-api-token --data-file=- --project=gcp-eiq
  ```
- [ ] Verify token is stored in GSM:
  ```bash
  gcloud secrets versions access latest --secret=gitlab-api-token --project=gcp-eiq | wc -c
  ```
- [ ] Run the idempotent schedule creator:
  ```bash
  export SECRET_PROJECT=gcp-eiq
  export GITLAB_API_URL="https://gitlab.com/api/v4"
  export PROJECT_ID="<YOUR_GITLAB_PROJECT_ID>"
  ./scripts/ci/create_dr_schedule.sh
  ```
- [ ] Verify schedule created in GitLab (Project → CI/CD → Schedules → should show "DR dry-run quarterly schedule").
- [ ] Close this issue once the schedule is confirmed active.

Reference:
- Ops Finalization Runbook: `docs/OPS_FINALIZATION_RUNBOOK.md` (Steps 1–3)
- Related: `issues/905-run-live-dr-dryrun.md`, `issues/904-credentials-for-dr-dryrun.md`

Note: This issue is a **direct follow-up** to the completed DR automation work. All scripts are idempotent and safe to re-run.
