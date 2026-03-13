# Setup Guide: GSM + Vault + KMS for Repo Secrets

Overview
- Use Google Secret Manager (GSM) as primary secret store for GCP resources.
- Use HashiCorp Vault (optional) for multi-cloud secret orchestration; back Vault with KMS.
- All secrets are encrypted with Cloud KMS keys. Cloud Build service account must have KMS decrypt rights.

Steps
1. Create KMS key ring & key:

```bash
gcloud kms keyrings create deployment-keys --location=global --project=nexusshield-prod
gcloud kms keys create deploy-key --location=global --keyring=deployment-keys --purpose=encryption --project=nexusshield-prod
```

2. Add secrets to GSM:

```bash
echo -n "$GITLAB_TOKEN" | gcloud secrets create gitlab-webhook-token --data-file=- --replication-policy="automatic" --project=nexusshield-prod
```

3. Grant Cloud Build service account access to secrets and KMS:

```bash
gcloud secrets add-iam-policy-binding gitlab-webhook-token --member=serviceAccount:service-PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor --project=nexusshield-prod
gcloud kms keys add-iam-policy-binding deploy-key --location=global --keyring=deployment-keys --member=serviceAccount:service-PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com --role=roles/cloudkms.cryptoKeyEncrypterDecrypter --project=nexusshield-prod
```

4. Reference secrets in `cloudbuild.yaml` using `secrets` and `availableSecrets` with `kmsKeyName`.

Notes
- Follow principle of least privilege. Use short-lived credentials where possible.
- Rotate keys periodically and automate rotation via Cloud Scheduler + rotation scripts.
