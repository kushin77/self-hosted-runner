## Rotate `github-token` in Google Secret Manager

This document explains how to rotate the `github-token` secret used by the
`prevent-releases` service. Follow these idempotent steps; they are safe to run
multiple times.

Steps:

1. Generate a new GitHub PAT with minimum scopes (repo:public_repo or repo scope as required).

2. Add the new version to GSM:

```bash
PROJECT=nexusshield-prod
echo -n "NEW_GITHUB_TOKEN_VALUE" | gcloud secrets versions add github-token --data-file=- --project="$PROJECT"
```

3. Ensure the Cloud Run service account has `roles/secretmanager.secretAccessor` on the secret (idempotent):

```bash
gcloud secrets add-iam-policy-binding github-token --project="$PROJECT" \
  --member="serviceAccount:nxs-prevent-releases-sa@$PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" || true
```

4. Restart the Cloud Run service to pick up the new secret version (optional - Cloud Run will mount latest):

```bash
gcloud run services update prevent-releases --project="$PROJECT" --region=us-central1 --quiet
```

5. Verify rotation: run a quick poll invocation and check logs and behavior.

6. Revoke or delete the old token in GitHub when confident.

Notes:
- Secrets are stored in GSM; prefer encrypted transfers and never commit token values.
- This process is idempotent and safe to run repeatedly.
