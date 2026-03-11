/**
 * Cloud Run Module - Serverless Container Deployment
 * Deploys backend and frontend containerized services
 */

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for deployment"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "service_name" {
  description = "Service name prefix for resource naming"
  type        = string
  default     = "nexus-shield"
}

variable "backend_image" {
  description = "Backend container image URL"
  type        = string
}

variable "frontend_image" {
  description = "Frontend container image URL"
  type        = string
}

variable "backend_memory" {
  description = "Backend container memory in MI"
  type        = string
  default     = "1Gi"
}

variable "backend_cpu" {
  description = "Backend CPU cores"
  type        = string
  default     = "1"
}

variable "frontend_memory" {
  description = "Frontend container memory in MI"
  type        = string
  default     = "512Mi"
}

variable "frontend_cpu" {
  description = "Frontend CPU cores"
  type        = string
  default     = "1"
}

variable "min_instances" {
  description = "Minimum number of instances"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

variable "timeout_seconds" {
  description = "Request timeout in seconds"
  type        = number
  default     = 60
}

variable "service_account_email" {
  description = "Service account email for backend"
  type        = string
}

variable "vpc_connector_name" {
  description = "VPC connector name for private database/cache access"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables for backend"
  type        = map(string)
  default     = {}
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for frontend"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    module = "cloud_run"
  }
}
