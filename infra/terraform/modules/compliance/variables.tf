/**
 * Compliance Module - Policy checks, resource audits, governance
 */

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "service_name" {
  description = "Service name"
  type        = string
  default     = "nexus-shield"
}

variable "labels" {
  description = "Labels for resources"
  type        = map(string)
  default     = {}
}
