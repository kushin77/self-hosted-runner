# Cloud Build Trigger + Scheduler (Terraform)

Purpose: Create the `gov-scan-trigger` Cloud Build trigger and a Cloud Scheduler job to run it daily. This module is idempotent and intended to be applied from a privileged deployment environment.

Prerequisites:
- `gcloud` and Terraform installed in the deployment environment.
- APIs enabled: `cloudbuild.googleapis.com`, `cloudscheduler.googleapis.com`, `secretmanager.googleapis.com`.
- The service account performing `terraform apply` must have: `roles/cloudbuild.admin`, `roles/cloudscheduler.admin`, `roles/secretmanager.secretAccessor`, and `roles/iam.serviceAccountUser`.

Quick start (as admin):

```bash
cd infra/cloudbuild
terraform init
terraform apply -var="project=$(gcloud config get-value project)" -var="scheduler_service_account=PROJECT_NUMBER@cloudscheduler.gserviceaccount.com"
```

Security notes:
- The `github_token_secret_name` variable should point to a Secret Manager secret containing a GitHub token with repo comment permissions. The module does not embed secrets in code; it references the secret name.
- This Terraform module is the recommended path for creating the trigger during first deployment to satisfy immutable, idempotent infrastructure requirements.
