# Variables for CronJob IRSA configuration
variable "cluster_oidc_issuer_url" {
  description = "The URL of the EKS cluster OIDC issuer"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket for archival"
  type        = string
  default     = ""
}

variable "secrets_arns" {
  description = "List of ARNs for secrets the CronJob can access"
  type        = list(string)
  default     = []
}
