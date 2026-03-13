variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for node groups"
  type        = list(string)
}

variable "node_group_name" {
  description = "Name of the EKS node group"
  type        = string
  default     = "primary"
}

variable "desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

variable "instance_types" {
  description = "List of instance types for node group"
  type        = list(string)
  default     = ["t3.xlarge"]
}

variable "disk_size" {
  description = "EBS volume size for worker nodes in GB"
  type        = number
  default     = 100
}

variable "enable_ssm_access" {
  description = "Enable SSM access to worker nodes"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = ""
}

variable "vault_namespace" {
  description = "Vault namespace for secret provider"
  type        = string
  default     = ""
}

variable "enable_secrets_store_csi" {
  description = "Enable Secrets Store CSI driver installation"
  type        = bool
  default     = true
}

variable "csi_driver_version" {
  description = "Version of the Secrets Store CSI driver"
  type        = string
  default     = "v1.3.4"
}
