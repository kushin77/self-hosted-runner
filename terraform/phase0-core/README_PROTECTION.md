Branch protection

This file contains Terraform that will set GitHub branch protection to require Cloud Build status checks.

Important:
- Applying requires a GitHub token with admin permissions. Run this only from an admin environment.
- The `cloud_build_status_contexts` must match the status check names emitted by Cloud Build for the repository.
- If you prefer to manage branch protection via the GitHub UI or org policy, do not run this file.

Apply steps:

```bash
cd terraform/phase0-core
terraform init
terraform apply -var="github_repo=REPO_NAME" -var="github_owner=ORG" -var="cloud_build_status_contexts=[\"cloudbuild\"]"
```