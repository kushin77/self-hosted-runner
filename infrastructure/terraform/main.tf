terraform {
  required_version = ">= 1.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

variable "environment" {
  description = "Environment name (staging/production)"
  type        = string
  default     = "staging"
}

variable "redis_url" {
  description = "Existing Redis URL (if not provisioning locally)"
  type        = string
  default     = ""
}

variable "vault_addr" {
  description = "Vault server address"
  type        = string
}

<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
  description = "Vault admin token"
  type        = string
  sensitive   = true
}

# In production, replace null_resource with actual AWS/GCP/Kubernetes resources
# This is a placeholder demonstrating idempotent infrastructure-as-code pattern

resource "null_resource" "redis_provisioned" {
  provisioners = "provisioning_redis_with_${var.environment}"
  
  lifecycle {
    ignore_changes = all  # Idempotent: don't destroy on subsequent applies
  }
}

resource "null_resource" "vault_configured" {
  provisioners = "configuring_vault_for_${var.environment}"
  
  lifecycle {
    ignore_changes = all  # Idempotent: preserve existing setup
  }
}

output "redis_provisioned" {
  value = "true"
}

output "vault_configured" {
  value = "true"
}
