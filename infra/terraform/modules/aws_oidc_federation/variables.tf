variable "github_repo" {
  description = "GitHub repository (owner/repo)"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID (for workload identity pool reference)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "role_name" {
  description = "IAM role name for OIDC provider"
  type        = string
  default     = "github-oidc-role"
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    phase      = "tier-2-aws-migration"
  }
}
