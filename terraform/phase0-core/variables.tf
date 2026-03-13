variable "gcp_project_id" {
  description = "GCP project id for NEXUS resources"
  type        = string
}

variable "gcp_region" {
  description = "Primary GCP region for resources"
  type        = string
}

variable "gcp_standby_region" {
  description = "Standby GCP region for HA resources"
  type        = string
}
