# Input variables for CI runners module

variable "project_name" {
  type        = string
  description = "Project name for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "runner_count" {
  type        = number
  description = "Number of runners to create"
  validation {
    condition     = var.runner_count >= 1 && var.runner_count <= 10
    error_message = "Runner count must be between 1 and 10."
  }
}

variable "instance_type_standard" {
  type        = string
  description = "Instance type for standard runners"
  default     = "t3.medium"
}

variable "instance_type_highmem" {
  type        = string
  description = "Instance type for high-memory runners"
  default     = "r5.xlarge"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for runner deployment"
  validation {
    condition     = startswith(var.vpc_id, "vpc-")
    error_message = "VPC ID must start with vpc-"
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for runner deployment"
  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet ID is required."
  }
}

variable "runner_token" {
  type        = string
  sensitive   = true
  description = "GitHub runner registration token (keep secure)"
  validation {
    condition     = length(var.runner_token) > 10
    error_message = "Runner token appears invalid (too short)"
  }
}

variable "github_owner" {
  type        = string
  description = "GitHub organization or user name"
  validation {
    condition     = length(var.github_owner) >= 1
    error_message = "GitHub owner is required."
  }
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
  validation {
    condition     = length(var.github_repo) >= 1
    error_message = "GitHub repo is required."
  }
}
