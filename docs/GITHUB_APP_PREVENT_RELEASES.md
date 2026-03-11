**GitHub App: Prevent Releases / Tags**

This document explains how to register and deploy the `prevent-releases` GitHub App scaffold included in `apps/prevent-releases`.

Steps (high-level):

1. Create a GitHub App (via GitHub UI):
   - Name: prevent-releases
   - Webhook URL: <CLOUD_RUN_URL>/api/webhooks
   - Webhook secret: generate a random value and store in GSM as `github-app-webhook-secret`
   - Permissions: Repositories: Contents (read/write), Issues (write)
   - Events: Create, Release
   - Generate a private key and note the App ID

2. Store App credentials in GSM:

```bash
GCP_PROJECT=nexusshield-prod
printf '%s' "<PRIVATE_KEY_PEM>" | gcloud secrets versions add github-app-private-key --data-file=- --project=${GCP_PROJECT}
printf '%s' "<APP_ID>" | gcloud secrets versions add github-app-id --data-file=- --project=${GCP_PROJECT}
gcloud secrets add-iam-policy-binding github-app-private-key --project=${GCP_PROJECT} --member="serviceAccount:nxs-automation-sa@${GCP_PROJECT}.iam.gserviceaccount.com" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding github-app-id --project=${GCP_PROJECT} --member="serviceAccount:nxs-automation-sa@${GCP_PROJECT}.iam.gserviceaccount.com" --role="roles/secretmanager.secretAccessor"
```

3. Deploy to Cloud Run (or your platform of choice). The container reads secrets and verifies webhook signatures.

4. Verify by attempting to create a release or push a tag — the App should remove it and create an audit issue.

Notes: registering the App requires GitHub UI steps (private key generation). The scaffold here is idempotent and stateless; logs and audit issues form the immutable trail.
