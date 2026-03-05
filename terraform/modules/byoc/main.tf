// BYOC Terraform module (Issue #11)
// This module will allow RunnerCloud control plane to be deployed into a
// customer VPC using ARC + Karpenter. The module is a thin wrapper around
// `ci-runners` with added OIDC configuration, cost tags, and VPC endpoints.
//
// For now this is a placeholder with variable definitions and README pointers.

terraform {
  required_version = ">= 1.0"
}

variable "customer_vpc_id" {
  type        = string
  description = "VPC ID where BYOC components will be deployed"
}

variable "oidc_provider_url" {
  type        = string
  description = "OIDC provider URL for RBAC control"
}

# TODO: implement BYOC control plane resources (ARC cluster, Karpenter)

output "note" {
  value = "BYOC module placeholder - implement weeks 8-9"
}
