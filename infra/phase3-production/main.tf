provider "google" {
  project = "nexusshield-prod"
  region  = "us-central1"
}

terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "terraform.tfstate"
  }
}

resource "google_service_account" "prod_deployer" {
  account_id   = "prod-deployer-sa-v3"
  display_name = "Production Deployer Service Account V3"
  project      = "nexusshield-prod"
}

resource "google_project_iam_member" "prod_deployer_roles" {
  for_each = toset([
    "roles/secretmanager.secretAccessor",
    "roles/storage.objectViewer",
    "roles/iam.serviceAccountTokenCreator",
    "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  ])
  project = "nexusshield-prod"
  role    = each.key
  member  = "serviceAccount:${google_service_account.prod_deployer.email}"
}

resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "github-actions-pool-v3"
  display_name              = "GitHub Actions Pool V3"
  description               = "Identity pool for GitHub Actions to authenticate to GCP"
  project                   = "nexusshield-prod"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  project                            = "nexusshield-prod"
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider-v3"
  display_name                       = "GitHub Actions Provider V3"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }
  attribute_condition = "assertion.repository == 'kushin77/self-hosted-runner'"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_sa_binding" {
  service_account_id = google_service_account.prod_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/kushin77/self-hosted-runner"
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github_provider.name
}

output "service_account_email" {
  value = google_service_account.prod_deployer.email
}
