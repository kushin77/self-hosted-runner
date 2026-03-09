output "vmss_id" {
  description = "The ID of the VM Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.vmss.id
}

output "vmss_name" {
  description = "The name of the VM Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.vmss.name
}

output "vmss_principal_id" {
  description = "The principal ID of the managed identity"
  value       = azurerm_linux_virtual_machine_scale_set.vmss.identity[0].principal_id
}

output "autoscale_setting_id" {
  description = "The ID of the autoscale setting (if enabled)"
  value       = var.enable_autoscaling ? azurerm_monitor_autoscale_setting.vmss_autoscale[0].id : null
}
