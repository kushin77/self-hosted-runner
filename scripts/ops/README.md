# Rotation tooling for uptime-check-token

This folder contains tooling to rotate the `uptime-check-token` Secret Manager secret
and update Cloud Run services to reference the latest version.

Files:
- `rotate-uptime-token.sh` — Generates a new token, adds a new secret version to GSM,
  and updates Cloud Run services using `gcloud run services update --update-secrets`.

Quick dry-run test:

```bash
DRY_RUN=1 ./scripts/ops/rotate-uptime-token.sh
```

To perform a real rotation (requires `gcloud` auth and proper IAM):

```bash
./scripts/ops/rotate-uptime-token.sh --project=nexusshield-prod --region=us-central1
```

Scheduling recommendations:
- Use Cloud Scheduler + Pub/Sub + Cloud Run job to call an authenticated endpoint that triggers rotation.
- Alternatively, create a Cloud Scheduler job that triggers this script from a secure CI runner (not GitHub Actions).

Security notes:
- The script uses Secret Manager and `gcloud` CLI; ensure the caller has `roles/secretmanager.secretVersionAdder` and `roles/run.admin` minimal privileges.
- Avoid logging token values to persistent logs.
