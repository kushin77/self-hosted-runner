variable "resource_group_name" {
  description = "Resource group to create resources in"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "vm_sku" {
  description = "VM size"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "capacity" {
  description = "Initial VMSS capacity"
  type        = number
  default     = 1
}

variable "admin_username" {
  description = "Admin username for VM instances"
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  default     = ""
}

variable "image_publisher" {
  type    = string
  default = "Canonical"
}

variable "image_offer" {
  type    = string
  default = "UbuntuServer"
}

variable "image_sku" {
  type    = string
  default = "22_04-lts-gen2"
}

variable "runner_labels" {
  description = "Labels for GitHub Actions runners"
  type        = list(string)
  default     = ["azure", "runner"]
}

variable "runner_group" {
  description = "Runner group for GitHub Actions"
  type        = string
  default     = "azure-scale-set"
}

variable "custom_script_command" {
  description = "Custom startup script for runner initialization"
  type        = string
  default     = ""
}

variable "enable_autoscaling" {
  description = "Enable automatic scaling based on metrics"
  type        = bool
  default     = true
}

variable "min_capacity" {
  description = "Minimum VMSS capacity for autoscaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum VMSS capacity for autoscaling"
  type        = number
  default     = 10
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
