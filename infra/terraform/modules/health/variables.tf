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

variable "enable_checks" {
  description = "Enable uptime checks"
  type        = bool
  default     = false
}

variable "backend_host" {
  description = "Host (no scheme) for backend uptime checks, e.g. api.example.com"
  type        = string
  default     = ""
}

variable "frontend_host" {
  description = "Host (no scheme) for frontend uptime checks, e.g. example.com"
  type        = string
  default     = ""
}

variable "auth_headers" {
  description = "Optional HTTP headers to include in uptime check requests (map). Use to pass Authorization header securely via CI/secret manager."
  type        = map(string)
  default     = {}
}
