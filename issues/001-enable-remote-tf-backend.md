Title: Enable remote Terraform backend with locking and snapshots

Description
- Configure a remote Terraform backend (S3/DynamoDB or equivalent) to store state, enable locking, and allow state snapshots.

Acceptance
- Add `backend.tf` to `terraform/` (values provided via CI secrets or Vault) or configure CI to inject `backend.s3.tf` at runtime.
- Ensure `ensure_tf_backend.sh` returns OK in CI before allowing `terraform apply`.

Owner: infra-team
Priority: high
