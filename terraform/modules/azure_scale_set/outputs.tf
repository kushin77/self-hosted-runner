output "vmss_id" {
  description = "The ID of the VM Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.vmss.id
}

output "vmss_name" {
  description = "The name of the VM Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.vmss.name
}
