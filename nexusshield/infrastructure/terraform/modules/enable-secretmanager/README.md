Module: enable-secretmanager

This module enables the Google Secret Manager API for a project using the
`google_project_service` resource. It is intentionally minimal and idempotent.

Usage (root Terraform configuration must configure the Google provider):

module "enable_secretmanager" {
  source  = "./modules/enable-secretmanager"
  project = "p4-platform"
}

Notes:
- The root Terraform must be configured with credentials that have
  `serviceusage.services.enable` (Project Owner / Service Usage Admin).
- This resource is safe to apply repeatedly and will not recreate other resources.
