# Main Terraform Configuration for GitHub Actions Self-Hosted Runners
# Provisions complete production-ready runner infrastructure

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment for remote backend
  # backend "s3" {
  #   bucket         = "your-tf-state-bucket"
  #   key            = "runners/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "self-hosted-runner"
    }
  }
}

# Input variables
variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Project name"
  default     = "elevatediq-runners"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "prod"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for runner deployment"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for runner deployment"
}

variable "runner_count" {
  type        = number
  description = "Total number of runners"
  default     = 2
}

variable "runner_token" {
  type        = string
  sensitive   = true
  description = "GitHub runner registration token (generate via GitHub Settings)"
}

variable "github_owner" {
  type        = string
  description = "GitHub organization or user name"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
}

# CI Runners module
module "runners" {
  source = "./modules/ci-runners"

  project_name            = var.project_name
  environment             = var.environment
  runner_count            = var.runner_count
  instance_type_standard  = "t3.medium"   # 2 vCPU, 4GB RAM
  instance_type_highmem   = "r5.xlarge"   # 4 vCPU, 32GB RAM
  vpc_id                  = var.vpc_id
  subnet_ids              = var.subnet_ids
  runner_token            = var.runner_token
  github_owner            = var.github_owner
  github_repo             = var.github_repo
}

# Outputs
output "standard_runner_ids" {
  description = "IDs of standard runner instances"
  value       = module.runners.standard_runner_ids
}

output "highmem_runner_ids" {
  description = "IDs of high-memory runner instances"
  value       = module.runners.highmem_runner_ids
}

output "standard_runner_private_ips" {
  description = "Private IPs of standard runners"
  value       = module.runners.standard_runner_private_ips
}

output "highmem_runner_private_ips" {
  description = "Private IPs of high-memory runners"
  value       = module.runners.highmem_runner_private_ips
}

output "security_group_id" {
  description = "Security group ID for runners"
  value       = module.runners.security_group_id
}
