## Privileged Cloud Build Trigger Setup (Action Required)

This file contains the exact, ready-to-run commands and required IAM roles for an administrator to create the scheduled Cloud Build trigger that runs the repository governance scanner.

Required roles for the account performing these steps:
- `roles/cloudbuild.builds.editor` or `roles/cloudbuild.admin` (to create triggers)
- `roles/secretmanager.secretAccessor` on the secret containing the GitHub token (default secret name: `github-token`)
- `roles/iam.serviceAccountUser` if using a service account impersonation flow

Recommended approach (admin runs these):

1) Create a GitHub-triggered build trigger (one-time):

```bash
gcloud beta builds triggers create github \
  --name="gov-scan-trigger" \
  --repo-name="self-hosted-runner" \
  --repo-owner="kushin77" \
  --branch-pattern="^main$" \
  --build-config="governance/cloudbuild-gov-scan.yaml" \
  --description="Governance scanner (manual/cron runner)."
```

2) Create a Cloud Scheduler job to run the trigger daily (example: 03:00 UTC):

First, give the Cloud Scheduler service account permission to run triggers (if needed):

```bash
PROJECT=$(gcloud config get-value project)
SCHED_SA="${PROJECT}@cloudscheduler.gserviceaccount.com"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:$SCHED_SA" --role="roles/cloudbuild.builds.editor"
```

Then create the scheduler job that calls `gcloud` via an App Engine or Cloud Run service, or directly invokes the Cloud Build REST API with a service account token. Simple example using `gcloud` invocation through a Cloud Run job (preferred for auditable invocation):

```bash
# Schedule: daily at 03:00 UTC
gcloud scheduler jobs create http gov-scan-daily \
  --schedule="0 3 * * *" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/$PROJECT/triggers/gov-scan-trigger:run" \
  --http-method=POST \
  --oauth-service-account-email="$SCHED_SA"
```

Alternative: run the trigger directly from Cloud Scheduler by calling the Cloud Build REST API with an OAuth 2.0 service account token.

Validation steps (admin):
- Run the trigger manually to verify it starts a build:

```bash
gcloud beta builds triggers run gov-scan-trigger --branch=main --project="$PROJECT"
```

- Confirm the build runs and completes. Inspect logs in Cloud Build, and verify that the governance scanner posted results to the audit issue `#2619` (script uses GitHub API to post results).

If the trigger creation fails due to IAM permissions, please grant the required roles to the account performing the operation and retry. When the trigger is created and validated, update or close issue `#2623` to record completion.

Contact: leave a comment on issue #2623 with the trigger name and the first run ID for audit immutability.
