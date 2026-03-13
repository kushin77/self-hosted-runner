variable "project_id" {
  description = "GCP project ID where bindings should be applied"
  type        = string
}

variable "gcp_region" {
  description = "GCP region (for provider)"
  type        = string
  default     = "us-central1"
}

variable "prod_deployer_sa_email" {
  description = "Email of the production deployer service account (serviceAccount:...@...gserviceaccount.com)"
  type        = string
}

variable "cloud_build_sa_email" {
  description = "Cloud Build service account email"
  type        = string
}

variable "backend_sa_email" {
  description = "Backend service account email to grant secrets/KMS access"
  type        = string
}

variable "frontend_sa_email" {
  description = "Frontend service account email to grant secrets access"
  type        = string
}

variable "cloud_scheduler_sa_email" {
  description = "Service account used by Cloud Scheduler (if applicable)"
  type        = string
  default     = ""
}

variable "milestone_sa_email" {
  description = "Service account that publishes to Pub/Sub for milestone organizer"
  type        = string
  default     = ""
}

variable "kms_crypto_key_resource_name" {
  description = "Full resource name for the KMS crypto key (projects/PROJECT/locations/LOCATION/keyRings/NAME/cryptoKeys/NAME)"
  type        = string
  default     = ""
}

variable "github_org" {
  description = "GitHub organization/owner (e.g., kushin77)"
  type        = string
  default     = "kushin77"
}

variable "github_repo_name" {
  description = "GitHub repository name (e.g., self-hosted-runner)"
  type        = string
  default     = "self-hosted-runner"
}
