output "public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.this.ip_address
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = azurerm_public_ip.this.fqdn
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.this.ip_address}"
}

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.this.name
}
