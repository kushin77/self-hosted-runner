variable "project" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "pool_id" {
  type = string
}

variable "provider_id" {
  type = string
}

variable "service_account_email" {
  type        = string
  description = "Email of the existing or new service account to allow impersonation"
}

variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}
