variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure location"
  type        = string
  default     = "eastus"
}

variable "vm_size" {
  description = "Size of VM instances"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "image_publisher" {
  description = "Image publisher"
  type        = string
  default     = "Canonical"
}

variable "image_offer" {
  description = "Image offer"
  type        = string
  default     = "UbuntuServer"
}

variable "image_sku" {
  description = "Image sku"
  type        = string
  default     = "18.04-LTS"
}
