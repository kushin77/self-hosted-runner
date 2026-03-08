// Example root module using infra/azure/azure_scale_set module

provider "azurerm" {
  features = {}
}

variable "resource_group_name" {
  type    = string
  default = "example-rg"
}

module "runners_vmss" {
  source              = "../../azure/azure_scale_set"
  name                = "example-vmss"
  resource_group_name = var.resource_group_name
  location            = "eastus"
}

// NOTE: Configure provider authentication via environment variables or a secure CI role.
