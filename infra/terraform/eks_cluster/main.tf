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

  # Create a VPC when none provided to allow unattended provisioning.
  create_vpc      = true
  vpc_cidr        = "10.0.0.0/16"

  # VPC inputs: if operator prefers to inject an existing VPC, set vpc_id/subnet_ids
  vpc_id          = var.vpc_id
  subnet_ids      = var.subnet_ids

  node_groups = var.node_groups

  manage_aws_auth = true

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
