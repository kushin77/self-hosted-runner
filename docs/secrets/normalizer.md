# Normalizer secrets (GSM + CSI)

This document explains how to provision Normalizer secrets in Google Secret Manager and use the GCP Secret Manager CSI driver to inject them into the Normalizer CronJob.

Provisioning (example):

```bash
# Create secret versions in nexusshield-prod
printf "%s" "REPLACE_WITH_API_KEY" | gcloud secrets create normalizer-api-key --data-file=- --project=nexusshield-prod || gcloud secrets versions add normalizer-api-key --data-file=- --project=nexusshield-prod
printf "%s" "REPLACE_WITH_DB_PASS" | gcloud secrets create normalizer-db-pass --data-file=- --project=nexusshield-prod || gcloud secrets versions add normalizer-db-pass --data-file=- --project=nexusshield-prod
```

Apply the SecretProviderClass and update the CronJob to mount the CSI volume and read env from the Kubernetes Secret created by the driver.

See `k8s/secretproviderclass-gsm.yaml` for the example SecretProviderClass.
