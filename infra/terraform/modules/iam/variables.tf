/**
 * IAM Module - Service Accounts and Role Bindings
 * Creates least-privilege service accounts for each workload
 */

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "service_name" {
  description = "Service name prefix for resource naming"
  type        = string
  default     = "nexus-shield"
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity Federation"
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "GitHub repository for OIDC (e.g., owner/repo)"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    module = "iam"
  }
}
