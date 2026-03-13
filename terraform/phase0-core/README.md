Phase0: GSM + KMS + Cloud Build Trigger

This Terraform module provisions:
- A Google KMS KeyRing and CryptoKey for encrypting secrets
- A Google Secret Manager secret (placeholder)
- IAM bindings so the Cloud Build service account can access secrets and use KMS
- A sample Cloud Build trigger that runs `cloudbuild.yaml` on pushes to the configured branch

Usage:
1. Configure `terraform.tfvars` or pass variables via CLI/environment.
2. `terraform init`
3. `terraform apply`

Important: Do NOT store secret values in this repository. Provide secret data via secure mechanisms (Terraform variables, CI variables, or `gcloud` when creating resources). Replace placeholder values before apply.