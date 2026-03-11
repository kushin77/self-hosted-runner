# Provision Deploy Service Account & GSM Key Runbook

Purpose
- Create a short-lived deploy service account and store its key in Google Secret Manager (GSM) so the runner can perform non-interactive deployments.

High-level steps (admin):

1. Apply Terraform in `infra/terraform/tmp_observability` to create the `sa-deploy-synthetic` service account and `deploy-sa-key` secret resource:

```bash
cd infra/terraform/tmp_observability
terraform init
terraform apply -var="project=$(gcloud config get-value project)" -auto-approve
```

2. Create a short-lived JSON key for the SA and add it as a secret version:

```bash
SA_EMAIL=$(terraform output -raw deploy_sa_email)
gcloud iam service-accounts keys create /tmp/sa-key.json --iam-account="$SA_EMAIL" --project=$(gcloud config get-value project)
gcloud secrets versions add deploy-sa-key --data-file=/tmp/sa-key.json --project=$(gcloud config get-value project)
shred -u /tmp/sa-key.json
```

3. (Optional, recommended) Restrict secret access to the runner's service account or human operators only.

4. Notify automation: create GitHub issue comment with secret name and confirm the runner has permission to access the secret.

Deployment (automation):
- On the runner, the automation will run:

```bash
cd infra/terraform/tmp_observability
./deploy_with_gsm.sh $(gcloud config get-value project) deploy-sa-key
```

Security notes:
- Prefer Workload Identity or short-lived keys over long-lived keys. Rotate keys frequently.
- Ensure the secret is stored in GSM with automatic replication and appropriate IAM bindings.
