output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "vm_names" {
  description = "Names of the created VMs"
  value       = { for k, v in azurerm_windows_virtual_machine.vm : k => v.name }
}

output "vm_public_ips" {
  description = "Public IP addresses for RDP access, keyed by VM"
  value       = { for k, v in azurerm_public_ip.pip : k => v.ip_address }
}

output "admin_username" {
  description = "Local administrator username for all VMs"
  value       = var.admin_username
}

output "extension_ids" {
  description = "Resource IDs of the config extension per VM. If 'terraform apply' completed without error, the extension already reported Succeeded (Terraform fails the apply on extension provisioning errors) — use these IDs with 'az resource show --ids <id>' if you want to re-check status later without re-running apply."
  value       = { for k, v in azurerm_virtual_machine_extension.config : k => v.id }
}

output "script_raw_url_used" {
  description = "The GitHub raw URL the extension downloaded setup.ps1 from"
  value       = var.script_raw_url
}
