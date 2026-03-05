variable "resource_group_name" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "vm_sku" {
  type    = string
  default = "Standard_DS2_v2"
}

variable "capacity" {
  type    = number
  default = 1
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "admin_ssh_public_key" {
  type    = string
  default = ""
}
