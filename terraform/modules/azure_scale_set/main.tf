terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features = {}
}

resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "runner-vmss"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku       = var.vm_sku
  instances = var.capacity

  admin_username = var.admin_username

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  rolling_upgrade_policy {
    max_batch_instance_percent = 20
  }

  upgrade_mode = "Manual"

  tags = {
    module = "azure_scale_set"
  }
}
