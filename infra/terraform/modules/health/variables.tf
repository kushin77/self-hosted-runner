/**
 * Health Checks Module - Uptime checks, SLOs, and synthetic monitoring
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

variable "backend_url" {
  description = "Backend service URL"
  type        = string
}

variable "frontend_url" {
  description = "Frontend service URL"
  type        = string
}

variable "api_status_path" {
  description = "Health API path"
  type        = string
  default     = "/api/v1/status"
}

variable "health_path" {
  description = "Health path"
  type        = string
  default     = "/health"
}
