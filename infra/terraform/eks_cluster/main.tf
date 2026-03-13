terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 19.0"

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
