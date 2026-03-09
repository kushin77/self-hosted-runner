Workload Identity module example

This module creates a GCP service account and binds a small set of roles suitable
for fetching secrets and reading storage blobs during bootstrap. Use the
`terraform/environments/staging-tenant-a/workload-identity.tf` example to adapt
for your staging project.

Notes:
- Replace `<replace-with-staging-project>` with your actual project id before
  running `terraform plan`.
- Review and restrict `roles` to the minimum required permissions.
