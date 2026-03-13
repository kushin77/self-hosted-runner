Org Admin Terraform - Review & Apply
===================================

Purpose
-------
This folder contains Terraform templates and guidance for org administrators to
approve and apply organization and project-level IAM/policy items required by
the security hardening effort (Milestone 2).

What this module does
---------------------
- Grants `roles/iam.serviceAccountAdmin` to the `prod-deployer-sa` service account
- Grants `roles/iam.serviceAccounts.create` to the Cloud Build service account
- Allows Cloud Build SA to impersonate the deployer SA (`roles/iam.serviceAccountTokenCreator`)
- Grants Secret Manager access to backend/frontend SAs
- Enables required Google APIs (Secret Manager, Cloud Build, Cloud KMS, Cloud Scheduler, Pub/Sub)
- Grants KMS `cryptoKeyEncrypterDecrypter` to backend SA
- Grants Pub/Sub publisher role for milestone organizer SA

What requires org admin action
------------------------------
The following items require org-level approval or actions that cannot be done
from a project-level unprivileged account. They are documented here for review
and include example commands and sample Terraform snippets.

1) Approve Cloud SQL org policy exception (production)
   - Org admins must review the policy and allow private/public IP exceptions
   - Example (gcloud):

```bash
# This is an example; change policy name/value as required
gcloud resource-manager org-policies allow --organization=ORGANIZATION_ID \
  --constraint=constraints/compute.restrictVpcPeering
```

2) Approve Cloud SQL org policy exception (staging)
   - Similar to (1) for the staging project/environment

3) Approve S3 `ObjectLock` requirement (AWS compliance)
   - This is on the AWS side; coordinate with AWS org admins to set bucket lifecycle and Object Lock

4) VPC-SC exceptions (cross-project access)
   - VPC-SC or access levels can only be changed by org admins. See
     https://cloud.google.com/vpc-service-controls/docs

5) Service account allowlist changes for worker SSH
   - If you maintain an allowlist policy, add the worker node IPs or service accounts

Applying this module
---------------------
1. Populate `terraform/org_admin/terraform.tfvars` with the required variable values
   - `project_id`, `prod_deployer_sa_email`, `cloud_build_sa_email`, `backend_sa_email`, etc.

2. From an environment with org/project admin privileges:

```bash
cd terraform/org_admin
terraform init
terraform plan -var-file=terraform.tfvars
# Review plan carefully
terraform apply -var-file=terraform.tfvars
```

Important notes
---------------
- Some items are intentionally left as examples or comments (org policies, VPC-SC,
  and AWS S3 ObjectLock) because applying them requires cross-org coordination.
- Do not run this from an unprivileged developer machine. Use a trusted admin
  bastion or CI job with org-level credentials.
- After applying, run `bash ../scripts/ops/production-verification.sh` to re-validate
  the deployment.

Contact
-------
If you need assistance applying these changes, ask the Security Architecture
team (owner: @kushin77). Provide the terraform plan output and audit links
for review.
