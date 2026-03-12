# Archival and Runner Apply Guide

This document explains how to apply the Terraform scaffolding to create the archival S3 bucket and how to deploy the Kubernetes CronJob runner.

Apply Terraform (S3 + KMS)

1. Review variables in `infra/terraform/archive_s3_bucket/variables.tf`.
2. Initialize and plan:

```bash
cd infra/terraform/archive_s3_bucket
terraform init
terraform plan -var="bucket_name=your-compliance-archive-bucket"
```

3. Apply with appropriate credentials (do not run with long-lived credentials stored in the repo):

```bash
terraform apply -var="bucket_name=your-compliance-archive-bucket" -auto-approve
```

4. Note outputs: `bucket_name`, `kms_key_arn`.

Deploy runner (Kubernetes CronJob)

1. Create a namespace `ops` and a service account with appropriate IAM role binding (IRSA) or node role that can upload to S3 and decrypt with KMS.
2. Ensure the runner can fetch `GH_TOKEN` securely at runtime via GSM, Vault, or KMS-decrypted secret. Implement as an init container or sidecar that writes the token to an in-memory volume.
3. Apply CronJob manifest:

```bash
kubectl apply -f k8s/milestone-organizer-cronjob.yaml
```

Security & Compliance
- Use OIDC→GSM/Vault/KMS to supply tokens; do NOT place tokens in repo.
- Configure S3 bucket lifecycle or Object Lock for immutability.
- Configure KMS key rotation and minimal key policy.

If you want, I can:
- Generate the exact `terraform apply` commands and PR-less commit the state bootstrap files for a specific bucket name you provide.
- Scaffold the IRSA role and Kubernetes service account binding for EKS.
