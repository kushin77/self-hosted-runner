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
  type    = string
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

module "monitoring" {
  source = "../modules/monitoring"

  project_id                = var.project_id
  environment               = var.environment
  service_name              = var.service_name
  notification_email        = "ops@example.com"
  enable_slack_notification = false
  labels                    = var.labels
}

module "logging" {
  source = "../modules/logging"

  project_id   = var.project_id
  environment  = var.environment
  service_name = var.service_name
  labels       = var.labels
}

# COMPLIANCE MODULE - DEFERRED TO PHASE 4.2 (IAM group creation needed)
# module "compliance" {
#   source = "../modules/compliance"
#
#   project_id   = var.project_id
#   environment  = var.environment
#   service_name = var.service_name
#   labels       = var.labels
# }
#
# HEALTH MODULE - DEFERRED TO PHASE 4.2 (resource_group validation + URL configuration)
# module "health" {
#   source = "../modules/health"
#
#   project_id   = var.project_id
#   environment  = var.environment
#   service_name = var.service_name
#   backend_url  = ""
#   frontend_url = ""
# }
