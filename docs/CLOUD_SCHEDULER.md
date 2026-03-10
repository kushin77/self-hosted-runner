# Cloud Scheduler + Pub/Sub Integration

This document describes the cloud-native alternative to on-host systemd timers using Cloud Scheduler and Pub/Sub. The repository includes Terraform resources to create two Pub/Sub topics and Scheduler jobs:

- `vault-sync-topic` — publishes every 15 minutes
- `ephemeral-cleanup-topic` — publishes daily at 03:00 UTC

These scheduler jobs only publish messages. You must deploy a Cloud Run service (or Cloud Function) that subscribes to these topics and executes the corresponding actions (Vault sync / ephemeral cleanup). This keeps automation immutable, idempotent, and hands-off.

Recommended approach:

1. Build a small container that performs the required actions on message receipt. Example responsibilities:
   - For `vault_sync`: call GSM to fetch secrets and write them to Vault (using `gcloud` + `vault` SDKs or API).
   - For `cleanup_ephemeral`: list instances with label `runner=ephemeral` and delete older than TTL.

2. Deploy the container as a Cloud Run service and create a push subscription to the Pub/Sub topic:

```bash
# Example deploy (replace IMAGE and SERVICE_NAME)
gcloud run deploy my-automation-service --image gcr.io/PROJECT/IMAGE --region=us-central1 --platform=managed --no-allow-unauthenticated

# Create subscription
gcloud pubsub subscriptions create vault-sync-sub --topic=vault-sync-topic --push-endpoint="https://my-automation-service-<hash>-uc.a.run.app/" --ack-deadline=60
```

3. Ensure the Cloud Run service has minimal service account permissions:
   - For Vault sync: `secretmanager.versions.access`, `secretmanager.secrets.get`, and `logging.logWriter`.
   - For cleanup: `compute.instances.list`, `compute.instances.delete`.
   - Use Workload Identity or Service Account bindings rather than long-lived keys.

Notes:
- The Terraform `cloud_scheduler.tf` file only creates topics and scheduler jobs; it does not deploy the Cloud Run service image. This keeps the infra idempotent and allows operators to provide their own container implementation.
- If you want me to create a reference container image (Dockerfile + entrypoint) that runs the existing scripts, I can add it and a small Makefile to build/push images to your registry.
