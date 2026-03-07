variable "aws_region" {
  type        = string
  description = "AWS region to create OIDC provider in"
  default     = "us-east-1"
}

variable "github_org" {
  type        = string
  description = "GitHub organization or user owning the repo"
}

variable "github_repo" {
  type        = string
  description = "Repository name"
}

variable "branch" {
  type        = string
  description = "Branch name to restrict OIDC tokens to"
  default     = "main"
}

variable "role_name" {
  type        = string
  description = "IAM role name to create for GitHub Actions OIDC"
  default     = "github-actions-oidc-role"
}
