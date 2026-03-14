variable "project_id" {
  description = "GCP project id"
  type        = string
}

variable "project_number" {
  description = "GCP project number"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "kms_location" {
  description = "KMS location (region)"
  type        = string
  default     = "us-central1"
}

variable "secret_id" {
  description = "Secret Manager secret id to create"
  type        = string
  default     = "nexus-app-secret"
}

variable "secret_data" {
  description = "(Sensitive) Secret payload for initial secret version. Pass via tfvars or environment."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_owner" {
  description = "GitHub owner/org for Cloud Build trigger"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name for the trigger"
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "Branch regex for the trigger (e.g. ^main$ or ^refs/heads/main$)"
  type        = string
  default     = "^main$"
}
