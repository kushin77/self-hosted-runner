variable "gcp_project" {
  type = string
}

variable "gcp_sa_name" {
  type    = string
  default = "github-actions-sa"
}

resource "google_service_account" "ci_sa" {
  account_id   = var.gcp_sa_name
  project      = var.gcp_project
  display_name = "GitHub Actions CI Service Account"
}

# Note: Workload Identity Provider configuration and binding to GitHub OIDC
# is typically performed via `google_iam_workload_identity_pool` resources
# and providers; this snippet is a placeholder reference and should be
# extended to create a Workload Identity Pool and Provider and a binding
# that allows the GitHub repo to impersonate the service account.

output "ci_service_account_email" {
  value = google_service_account.ci_sa.email
}
