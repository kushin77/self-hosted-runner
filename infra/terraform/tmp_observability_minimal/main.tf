terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
  default = "us-central1"
}

variable "environment" {
  type = string
}

variable "service_name" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

# Minimal observability: deploy logging infrastructure only
# (Monitoring/compliance/health moved to Phase 4 after metric/alert fixes)

module "logging" {
  source = "../modules/logging"

  project_id   = var.project_id
  environment  = var.environment
  service_name = var.service_name
  labels       = var.labels
}

output "audit_logs_bucket" {
  value = module.logging.audit_logs_bucket_name
}

output "application_logs_bucket" {
  value = module.logging.application_logs_bucket_name
}
