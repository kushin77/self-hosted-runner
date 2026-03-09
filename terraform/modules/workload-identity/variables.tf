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

