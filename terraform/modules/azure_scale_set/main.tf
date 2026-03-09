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

# VM Scale Set for GitHub Actions runners
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "runner-vmss-${var.environment}"
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

  identity {
    type = "SystemAssigned"
  }

  # Custom data for runner initialization
  custom_data = base64encode(var.custom_script_command != "" ? var.custom_script_command : local.default_init_script)

  tags = merge(
    {
      module      = "azure_scale_set"
      environment = var.environment
      runner_group = var.runner_group
      labels      = join(",", var.runner_labels)
    },
    var.tags
  )

  lifecycle {
    ignore_changes = [instances]
  }
}

# Autoscaling configuration
resource "azurerm_monitor_autoscale_setting" "vmss_autoscale" {
  count = var.enable_autoscaling ? 1 : 0

  name                = "vmss-autoscale-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss.id

  profile {
    name = "default"

    capacity {
      default = var.capacity
      minimum = var.min_capacity
      maximum = var.max_capacity
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}

# Local variables
locals {
  default_init_script = <<-EOF
              #!/bin/bash
              set -e
              echo "Initializing GitHub Actions runner on Azure..."
              
              # Update system
              apt-get update && apt-get upgrade -y
              
              # Install runner dependencies
              apt-get install -y \
                curl \
                wget \
                git \
                jq \
                unzip \
                docker.io
              
              # Setup Docker daemon
              systemctl start docker
              systemctl enable docker
              
              # Add runner user
              useradd -m -s /bin/bash runner || true
              usermod -aG docker runner || true
              
              echo "Runner initialization complete"
            EOF
}
