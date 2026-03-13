output "cluster_id" {
  description = "The ID/name of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "The Kubernetes server version for the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required for cluster authentication"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = try(aws_eks_cluster.main.identity[0].oidc[0].issuer, null)
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for IRSA"
  value       = aws_iam_openid_connect_provider.cluster_oidc.arn
}

output "node_group_id" {
  description = "EKS node group id"
  value       = aws_eks_node_group.main.id
}

output "node_group_arn" {
  description = "Amazon Resource Name (ARN) of the EKS Node Group"
  value       = aws_eks_node_group.main.arn
}

output "node_group_launch_template" {
  description = "Attributes of the launch template associated with the node group"
  value       = try(aws_eks_node_group.main.launch_template, null)
}

output "node_group_role_arn" {
  description = "IAM role ARN of the EKS Node Group"
  value       = aws_iam_role.node_group_role.arn
}

output "node_group_role_name" {
  description = "IAM role name of the EKS Node Group"
  value       = aws_iam_role.node_group_role.name
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster_security_group.id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = aws_security_group.node_group_sg.id
}

output "secrets_store_csi_driver_role_arn" {
  description = "ARN of the Secrets Store CSI Driver IAM role"
  value       = aws_iam_role.secrets_store_csi_driver_role.arn
}

output "vault_provider_role_arn" {
  description = "ARN of the Vault Secrets Provider IAM role"
  value       = aws_iam_role.vault_provider_role.arn
}

output "gsm_provider_role_arn" {
  description = "ARN of the GSM Secrets Provider IAM role"
  value       = aws_iam_role.gsm_provider_role.arn
}

output "workloads_namespace" {
  description = "Kubernetes namespace for application workloads"
  value       = kubernetes_namespace.workloads.metadata[0].name
}

output "cron_jobs_namespace" {
  description = "Kubernetes namespace for CronJob runner"
  value       = kubernetes_namespace.cron_jobs.metadata[0].name
}

output "secrets_store_csi_driver_installed" {
  description = "Whether the Secrets Store CSI driver was installed"
  value       = var.enable_secrets_store_csi ? true : false
}
