###############################################################################
# llm01 — Large LLM
###############################################################################

output "llm01_public_ip" {
  description = "llm01 public IP"
  value       = azurerm_public_ip.gemma.ip_address
}

output "llm01_private_ip" {
  description = "llm01 private IP (for VNet access)"
  value       = azurerm_network_interface.gemma.private_ip_address
}

output "llm01_ssh" {
  description = "SSH to llm01"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.gemma.ip_address}"
}

output "llm01_fqdn" {
  description = "llm01 FQDN"
  value       = azurerm_public_ip.gemma.fqdn
}

###############################################################################
# llm02 — Small/Medium/Vision LLM
###############################################################################

output "llm02_public_ip" {
  description = "llm02 public IP"
  value       = azurerm_public_ip.phi.ip_address
}

output "llm02_private_ip" {
  description = "llm02 private IP (for VNet access)"
  value       = azurerm_network_interface.phi.private_ip_address
}

output "llm02_ssh" {
  description = "SSH to llm02"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.phi.ip_address}"
}

output "llm02_fqdn" {
  description = "llm02 FQDN"
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
# Service endpoints (abstract names, from workstation via private IPs)
###############################################################################

output "vllm_large_llm_endpoint" {
  description = "Large LLM vLLM API endpoint"
  value       = "http://${azurerm_network_interface.gemma.private_ip_address}:${var.vllm_port}/v1"
}

output "vllm_small_llm_endpoint" {
  description = "Small LLM vLLM API endpoint"
  value       = "http://${azurerm_network_interface.phi.private_ip_address}:${var.phi_port}/v1"
}

output "vllm_vision_llm_endpoint" {
  description = "Vision LLM vLLM API endpoint"
  value       = "http://${azurerm_network_interface.phi.private_ip_address}:${var.qwen_vl_port}/v1"
}

output "vllm_medium_llm_endpoint" {
  description = "Medium LLM vLLM API endpoint"
  value       = "http://${azurerm_network_interface.phi.private_ip_address}:${var.devstral_port}/v1"
}

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.this.name
}
