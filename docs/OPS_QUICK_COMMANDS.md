Ops quick commands

This PR adds helper scripts for common quick ops tasks.

Grant Cloud Build log access (bucket-level least-privilege):

```
BUCKET_NAME=projects/_/logs/my-cloudbuild-logs ./scripts/ops/grant-cloudbuild-log-access.sh
```

Project-level alternative (broader):

```
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member="serviceAccount:deployer-run@nexusshield-prod.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

Run SBOM & Trivy on the approved host and upload results to GCS:

```
# on approved host (192.168.168.42)
./scripts/ops/run-sbom-and-trivy-on-approved-host.sh nexusshield-backend:local gs://nexusshield-dev-sbom-archive/2026-03-12
```

Notes:
- These are small utilities to standardize remediation steps and improve reproducibility.
- If you prefer, I can include explicit bucket names and automate a scheduled upload job in Cloud Build/CI.