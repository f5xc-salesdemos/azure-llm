###############################################################################
# Gemma VM
###############################################################################

output "gemma_public_ip" {
  description = "Gemma VM public IP"
  value       = azurerm_public_ip.gemma.ip_address
}

output "gemma_private_ip" {
  description = "Gemma VM private IP (for VNet access)"
  value       = "10.0.0.10"
}

output "gemma_ssh" {
  description = "SSH to Gemma VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.gemma.ip_address}"
}

output "gemma_fqdn" {
  description = "Gemma VM FQDN"
  value       = azurerm_public_ip.gemma.fqdn
}

###############################################################################
# Phi VM
###############################################################################

output "phi_public_ip" {
  description = "Phi VM public IP"
  value       = azurerm_public_ip.phi.ip_address
}

output "phi_private_ip" {
  description = "Phi VM private IP (for VNet access)"
  value       = "10.0.0.11"
}

output "phi_ssh" {
  description = "SSH to Phi VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.phi.ip_address}"
}

output "phi_fqdn" {
  description = "Phi VM FQDN"
  value       = azurerm_public_ip.phi.fqdn
}

###############################################################################
# Workstation VM
###############################################################################

output "workstation_public_ip" {
  description = "Workstation VM public IP"
  value       = azurerm_public_ip.workstation.ip_address
}

output "workstation_ssh" {
  description = "SSH to Workstation VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.workstation.ip_address}"
}

output "workstation_fqdn" {
  description = "Workstation VM FQDN"
  value       = azurerm_public_ip.workstation.fqdn
}

###############################################################################
# Service endpoints (from workstation, use private IPs)
###############################################################################

output "vllm_gemma_endpoint" {
  description = "Gemma vLLM API endpoint (from workstation)"
  value       = "http://10.0.0.10:${var.vllm_port}/v1"
}

output "vllm_phi_endpoint" {
  description = "Phi vLLM API endpoint (from workstation)"
  value       = "http://10.0.0.11:${var.vllm_port}/v1"
}

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.this.name
}
