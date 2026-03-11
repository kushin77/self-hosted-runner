# Terraform configuration for Phase 2 Multi-Layer Secrets Orchestration
# Consolidated provider setup for GCP, AWS, and Vault

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
}

# GCP Provider
provider "google" {
  project = var.gcp_project_id
  region  = "us-central1"
}

# AWS Provider
provider "aws" {
  region = var.aws_region
}

# Vault Provider
provider "vault" {
  address   = var.vault_addr
  namespace = var.vault_namespace
}

# Global variables
variable "gcp_project_id" {
  type        = string
  description = "GCP project ID"
  default     = "nexusshield-prod"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "vault_addr" {
  type        = string
  description = "Vault server address"
  default     = "https://vault.nexusshield.internal:8200"
}

variable "vault_namespace" {
  type        = string
  description = "Vault namespace"
  default     = "nexusshield"
}
