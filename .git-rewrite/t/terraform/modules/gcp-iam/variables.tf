variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "sa_name" {
  description = "The name of the service account"
  type        = string
  default     = "vault-ops-sa"
}
