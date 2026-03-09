# Azure Scale Set Module

This module provisions an Azure Virtual Machine Scale Set designed for use as a GitHub Actions runner pool.
It supports automatic scaling, custom initialization scripts, and comprehensive configuration for production deployments.

## Features

- **VM Scale Set Management:** Creates and manages Azure Linux VM Scale Sets
- **Autoscaling:** Optional automatic scaling based on CPU metrics (scale out at 70%, in at 30%)
- **Runner Configuration:** Support for GitHub Actions runner labels and groups
- **Custom Initialization:** Extensible boot script for runner setup and configuration
- **Managed Identity:** System-assigned managed identity for Azure service integration
- **Tag Management:** Comprehensive tagging strategy for resource organization and governance
- **Manual Upgrade Mode:** Controlled, safe upgrade processes for runner instances

## Module Variables

| Variable | Type | Description | Default |
|----------|------|---|---|
| `resource_group_name` | string | Azure Resource Group for resources | Required |
| `location` | string | Azure region | `eastus` |
| `vm_sku` | string | VM size (e.g., `Standard_DS2_v2`) | `Standard_DS2_v2` |
| `capacity` | number | Initial number of instances | `1` |
| `admin_username` | string | VM admin user | `azureuser` |
| `admin_ssh_public_key` | string | SSH public key for access | `` |
| `runner_labels` | list(string) | GitHub runner labels | `["azure", "runner"]` |
| `runner_group` | string | GitHub runner group name | `azure-scale-set` |
| `custom_script_command` | string | Custom initialization script | `` |
| `enable_autoscaling` | bool | Enable auto-scaling | `true` |
| `min_capacity` | number | Minimum instances for scaling | `1` |
| `max_capacity` | number | Maximum instances for scaling | `10` |
| `environment` | string | Environment name (dev/staging/prod) | `prod` |
| `tags` | map(string) | Additional resource tags | `{}` |
| `image_publisher` | string | VM image publisher | `Canonical` |
| `image_offer` | string | VM image offer | `UbuntuServer` |
| `image_sku` | string | VM image SKU | `22_04-lts-gen2` |

## Module Outputs

| Output | Description |
|--------|---|
| `vmss_id` | The ID of the VM Scale Set |
| `vmss_name` | The name of the VM Scale Set |
| `vmss_principal_id` | The principal ID of the managed identity |
| `autoscale_setting_id` | ID of the autoscale setting (if enabled) |

## Usage

See `examples/azure-scale` for complete usage example.

### Basic Example

```hcl
module "azure_scale_set" {
  source = "../../modules/azure_scale_set"

  resource_group_name  = azurerm_resource_group.runners.name
  location             = azurerm_resource_group.runners.location
  vm_sku               = "Standard_DS2_v2"
  capacity             = 3
  admin_username       = "azureuser"
  admin_ssh_public_key = var.admin_ssh_public_key
  
  runner_labels = ["azure", "production", "linux"]
  runner_group  = "prod-azure-runners"
  
  enable_autoscaling = true
  min_capacity       = 2
  max_capacity       = 20
  
  environment = "production"
  
  tags = {
    CostCenter = "Engineering"
    Team       = "DevOps"
  }
}
```

## Autoscaling

The module includes an optional autoscaling configuration that:
- **Scales out** (adds instances) when CPU > 70% for 5 minutes
- **Scales in** (removes instances) when CPU < 30% for 5 minutes
- Respects minimum and maximum capacity limits
- Includes 5-minute cooldown between scaling actions

To disable autoscaling, set `enable_autoscaling = false`.

## Custom Initialization

Use the `custom_script_command` variable to provide a custom startup script for runner initialization:

```hcl
module "azure_scale_set" {
  # ... other configuration ...
  
  custom_script_command = <<-EOF
    #!/bin/bash
    set -e
    echo "Custom runner initialization"
    # Your custom setup commands here
  EOF
}
```

If not provided, a default initialization script is used that installs Docker and runner dependencies.

## Related Documentation

- [Azure Capacity Planning Guide](../../../docs/AZURE_SCALE_SET_CAPACITY_PLANNING.md)
- [Azure Runner Migration Guide](../../../docs/AZURE_RUNNER_MIGRATION.md)
