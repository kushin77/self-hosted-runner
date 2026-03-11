variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "cloud_run_sa_email" {
  description = "Cloud Run service account email that needs access to secrets"
  type        = string
}
