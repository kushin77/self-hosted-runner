# Trigger Creation Needed — Privileged Action Required

Date: 2026-03-11

Status: BLOCKED — attempted automated creation failed due to GCP IAM permissions.

Active account used for attempt:

```text
$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
```

Observed error:

"PERMISSION_DENIED: The caller does not have permission. This command is authenticated as the active account specified by the [core/account] property."

What to do (admin):

1) Grant the required roles to the active account, or run the commands below as an admin/service account with the roles:

- `roles/cloudbuild.builds.editor` or `roles/cloudbuild.admin`
- `roles/secretmanager.secretAccessor` for the `github-token` secret
- `roles/iam.serviceAccountUser` if you will impersonate another SA

2) Run these commands (copy/paste as admin):

```bash
# create the Cloud Build trigger
gcloud beta builds triggers create github \
  --name="gov-scan-trigger" \
  --repo-name="self-hosted-runner" \
  --repo-owner="kushin77" \
  --branch-pattern="^main$" \
  --build-config="governance/cloudbuild-gov-scan.yaml" \
  --description="Governance scanner (manual/cron runner)." --project=$(gcloud config get-value project)

# validate by running it once
gcloud beta builds triggers run gov-scan-trigger --branch=main --project=$(gcloud config get-value project)
```

3) After creation and first run, post a comment on issue #2623 with the trigger name and build ID and close the issue.

Runbook (detailed): governance/PRIVILEGED_TRIGGER_SETUP.md

Notes:
- This file is an immutable, in-repo audit artifact recording the attempt and required admin steps.
