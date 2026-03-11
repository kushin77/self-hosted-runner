/**
 * VPC Networking Module - Network Infrastructure
 * Creates VPC, subnets, VPC connector, NAT gateway, and firewall rules
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

variable "primary_subnet_cidr" {
  description = "CIDR for primary subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "cloud_run_subnet_cidr" {
  description = "CIDR for Cloud Run VPC connector subnet"
  type        = string
  default     = "10.1.0.0/20"
}

variable "enable_nat" {
  description = "Enable Cloud NAT for outbound traffic"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    module = "vpc_networking"
  }
}
