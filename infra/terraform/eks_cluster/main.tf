terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
        # Constrain provider to <6.0 to avoid AWS provider v6 schema changes
        # that remove legacy launch template blocks used by the module.
        version = ">= 4.33.0, < 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  # Pin to a tested 18.x release to avoid newer module constructs incompatible
  # with the current provider/module mix. We'll validate and iterate as needed.
  version         = "~> 18.29"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # If `vpc_id`/`subnet_ids` are empty, the module will create networking by default.
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Create managed node groups via the module's supported variable
  eks_managed_node_groups = var.eks_managed_node_groups

  tags = merge(var.tags, { "Name" = var.cluster_name })
}

output "cluster_name" {
  value = module.eks.cluster_id
}

output "kubeconfig_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
