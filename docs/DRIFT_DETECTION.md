Terraform Drift Detection

This repository includes a Kubernetes CronJob to run a daily Terraform drift check against `terraform/phase0-core`.

Files added:
- `k8s/cronjobs/drift-detection.yaml` — CronJob manifest. Adjust `schedule`, `PROJECT_ID`, and secrets before deploying.
- `scripts/ops/drift/run_drift.sh` — Script that runs `terraform plan` and posts a summary to Slack if `SLACK_WEBHOOK` is provided.

Deployment steps (ops):

1. Create a namespace `ops` and a service account `terraform-runner-sa` with permissions to read the repo and run Terraform.
2. Create a Kubernetes secret `gcp-ops-sa-key` containing the GCP service account JSON with access to Secret Manager, KMS, and Cloud Build IAM as needed.
3. Create a Kubernetes secret `ops-secrets` with `slack_webhook` key set to the webhook URL for alerts.
4. Apply the CronJob manifest:

```bash
kubectl apply -f k8s/cronjobs/drift-detection.yaml
```

5. Monitor job runs in the `ops` namespace and view logs to verify.

Notes:
- The CronJob clones the repository and runs the drift script; ensure network access and Git credentials if the repo is private.
- You can also run the script from Cloud Run or Cloud Scheduler instead of a Kubernetes CronJob.
