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
