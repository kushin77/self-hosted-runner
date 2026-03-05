variable "project" {
  description = "GCP project where the service account will be created"
  type        = string
}

variable "service_account_id" {
  description = "Short id for the service account (no @)"
  type        = string
}

variable "display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "Runner service account"
}

variable "roles" {
  description = "List of IAM roles to bind to the service account"
  type        = list(string)
  default     = []
}
variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "service_account_name" {
  description = "Short name for the runner service account"
  type        = string
  default     = "runner-staging"
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "Runner service account (staging)"
}

variable "roles" {
  description = "List of IAM roles to bind to the service account"
  type        = list(string)
  default     = ["roles/secretmanager.secretAccessor"]
}
