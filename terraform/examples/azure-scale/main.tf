module "azure_scale_set" {
  source = "../../modules/azure_scale_set"

  resource_group_name  = var.resource_group_name
  location             = var.location
  vm_sku               = var.vm_sku
  capacity             = var.capacity
  admin_username       = var.admin_username
  admin_ssh_public_key = var.admin_ssh_public_key
}

output "vmss_id" {
  value = module.azure_scale_set.vmss_id
}
