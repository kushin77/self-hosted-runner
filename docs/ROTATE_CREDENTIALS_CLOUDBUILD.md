**Rotate Credentials via Cloud Build**

Purpose: provide a safe, auditable runner to execute `scripts/secrets/rotate-credentials.sh` in Cloud Build using Google Secret Manager secrets as runtime inputs.

Prerequisites:
- GSM secrets must exist: `github-token`, `vault-example-role-secret_id`, `aws-access-key-id`, `aws-secret-access-key`.
- Cloud Build service account must have `secretmanager.versions.access` and permission to run builds.

How to run manually:

1. From a secure admin environment, trigger Cloud Build with the provided config:

```bash
gcloud builds submit --config=cloudbuild/rotate-credentials-cloudbuild.yaml \
  --substitutions=PROJECT_ID=your-gcp-project,_REPO_OWNER=kushin77,_REPO_NAME=self-hosted-runner,_BRANCH=main
```

Notes:
- The Cloud Build config pulls secrets from GSM and injects them as environment variables for the build step; they are not printed to logs.
- Review audit logs in Cloud Build and GSM after completion.
