variable "region" {
  type    = string
  default = "us-east-1"
}

variable "thumbprint" {
  type = string
  description = "OIDC provider thumbprint (SHA1)"
}

variable "role_name" {
  type = string
  default = "github-actions-oidc-role"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type = string
  default = "main"
}
