variable "project" {
  description = "GCP project id"
  type        = string
}

variable "access_token" {
  description = "GCP access token for authentication"
  type        = string
  sensitive   = true
  default     = ""
}

variable "location" {
  description = "Location for scheduler (region)"
  type        = string
  default     = "us-central1"
}

variable "scheduler_service_account" {
  description = "Service account email used by Cloud Scheduler to run the trigger"
  type        = string
}

variable "github_token_secret_name" {
  description = "Secret Manager secret name that stores the GitHub token (full resource name or short id)"
  type        = string
  default     = "github-token"
}
