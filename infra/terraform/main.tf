/**
 * GCP Provider Configuration
 * Infrastructure-as-Code for NexusShield Portal
 * 
 * Immutable: All resources deployed through Terraform
 * Ephemeral: Temporary resources created/destroyed per deployment
 * Idempotent: Safe to apply multiple times
 * GSM/Vault/KMS: All credentials resolved from multi-cloud
 */

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # State file in GCS (immutable remote state)
  backend "gcs" {
    bucket = "nexusshield-terraform-state"
    prefix = "production"
  }
}

# Primary GCP provider
provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project
  region  = var.gcp_region
}

################################################################################
# Data Sources - Read-only references
################################################################################

data "google_client_config" "current" {}

################################################################################
# Local Variables
################################################################################

locals {
  environment = var.environment
  namespace   = "nexusshield"
  labels = {
    environment = var.environment
    managed-by  = "terraform"
    project     = "nexusshield"
    created-at  = timestamp()
  }
}
