variable "project_id" {
  description = "GCP project id where resources will be created"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "kms_location" {
  description = "Location for KMS key ring (e.g. global, us-central1)"
  type        = string
  default     = "global"
}

variable "kms_key_ring" {
  description = "KMS key ring name"
  type        = string
  default     = "nexusshield"
}

variable "kms_key" {
  description = "KMS crypto key name"
  type        = string
  default     = "mirror-key"
}

variable "wif_pool_id" {
  description = "Workload Identity Pool id"
  type        = string
  default     = "secrets-pool"
}

variable "wif_provider_id" {
  description = "Workload Identity Provider id"
  type        = string
  default     = "secrets-provider"
}

variable "wif_issuer" {
  description = "OIDC issuer URI for the workload identity provider"
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}
