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
$PLACEHOLDER
printf '%s' "<APP_ID>" | gcloud secrets versions add github-app-id --data-file=- --project=${GCP_PROJECT}
gcloud secrets add-iam-policy-binding github-app-private-key --project=${GCP_PROJECT} --member="serviceAccount:nxs-automation-sa@${GCP_PROJECT}.iam.gserviceaccount.com" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding github-app-id --project=${GCP_PROJECT} --member="serviceAccount:nxs-automation-sa@${GCP_PROJECT}.iam.gserviceaccount.com" --role="roles/secretmanager.secretAccessor"
```

3. Deploy to Cloud Run (or your platform of choice). Recommended production configuration:

- Allow unauthenticated Cloud Run invocations to receive GitHub webhook POSTs — the service enforces HMAC verification server-side.
- Inject secrets from Google Secret Manager into the Cloud Run revision (example using gcloud):

```bash
gcloud run deploy prevent-releases \
   --project=nexusshield-prod --region=us-central1 --image=IMAGE_URL \
   --service-account=nxs-prevent-releases-sa@nexusshield-prod.iam.gserviceaccount.com \
   --allow-unauthenticated \
   --set-secrets="GITHUB_WEBHOOK_SECRET=github-app-webhook-secret:latest" \
   --set-secrets="GITHUB_TOKEN=github-app-token:latest" \
   --quiet
```

The application will continue to verify the webhook HMAC and reject unauthorized calls. This pattern preserves an immutable audit trail while allowing GitHub to deliver webhooks reliably.

4. Verify by attempting to create a release or push a tag — the App should remove it and create an audit issue.

Notes: registering the App requires GitHub UI steps (private key generation). The scaffold here is idempotent and stateless; logs and audit issues form the immutable trail.
