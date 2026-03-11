# Cloud Build Trigger Setup for Governance Scanner

This document provides the steps and commands to create a Cloud Build trigger that runs the governance scanner on a schedule.

## Prerequisites

- GCP project: `nexusshield-prod`
- GitHub token stored in Secret Manager at `_GITHUB_TOKEN_SECRET=github-token`
- Service account with `roles/cloudbuild.builds.editor` or `roles/cloudbuild.admin` permissions

## Quick Start

Run the following command with an account that has Cloud Build admin permissions:

```bash
gcloud beta builds triggers create github \
  --name=governance-scan-trigger \
  --repo-name=self-hosted-runner \
  --repo-owner=kushin77 \
  --branch-pattern="^main$" \
  --build-config=governance/cloudbuild-gov-scan.yaml \
  --project=nexusshield-prod
```

## Verification

Once the trigger is created, you can:

1. **Manual trigger (immediate test):**
   ```bash
   gcloud builds submit --config=governance/cloudbuild-gov-scan.yaml \
     --project=nexusshield-prod \
     --substitutions=_GITHUB_TOKEN_SECRET="github-token"
   ```

2. **View trigger status:**
   ```bash
   gcloud beta builds triggers list --project=nexusshield-prod --filter="name:governance-scan-trigger"
   ```

3. **View build history:**
   ```bash
   gcloud builds list --project=nexusshield-prod --filter="substitutions._GITHUB_TOKEN_SECRET:github-token"
   ```

## Scheduling (Optional)

To run the scanner on a schedule (e.g., daily at 2 AM UTC via Cloud Scheduler):

1. Create a Cloud Scheduler job:
   ```bash
   gcloud scheduler jobs create http governance-scan-scheduled \
     --schedule="0 2 * * *" \
     --uri="https://cloudbuild.googleapis.com/v1/projects/nexusshield-prod/triggers/governance-scan-trigger:run" \
     --http-method=POST \
     --project=nexusshield-prod \
     --message-body='{}' \
     --oidc-service-account-email=<YOUR-SA-EMAIL> \
     --oidc-token-audience="https://cloudbuild.googleapis.com"
   ```

## Findings & Escalations

All scan findings are posted to the audit issue:
- Canonical audit issue: https://github.com/kushin77/self-hosted-runner/issues/2619

When violations are detected, the scanner will:
1. Post findings to the audit issue
2. Create individual `governance/escalation` issues for human review

## Configuration

- Build config: `governance/cloudbuild-gov-scan.yaml`
- Scanner script: `tools/governance-scan.sh`
- Scanner docs: `governance/ENFORCEMENT.md`

All scripts are idempotent, ephemeral, and safe to re-run.
