###############################################################################
# llm01 — Large LLM
###############################################################################

output "llm01_public_ip" {
  description = "llm01 public IP"
  value       = var.llm01_deployed ? azurerm_public_ip.llm01[0].ip_address : null
}

output "llm01_private_ip" {
  description = "llm01 private IP (for VNet access)"
  value       = var.llm01_deployed ? azurerm_network_interface.llm01[0].private_ip_address : null
}

output "llm01_ssh" {
  description = "SSH to llm01"
  value       = var.llm01_deployed ? "ssh ${var.admin_username}@${azurerm_public_ip.llm01[0].ip_address}" : null
}

output "llm01_fqdn" {
  description = "llm01 FQDN"
  value       = var.llm01_deployed ? azurerm_public_ip.llm01[0].fqdn : null
}

###############################################################################
# llm02 — Small/Medium/Vision LLM
###############################################################################

output "llm02_public_ip" {
  description = "llm02 public IP"
  value       = var.llm02_deployed ? azurerm_public_ip.llm02[0].ip_address : null
}

output "llm02_private_ip" {
  description = "llm02 private IP (for VNet access)"
  value       = var.llm02_deployed ? azurerm_network_interface.llm02[0].private_ip_address : null
}

output "llm02_ssh" {
  description = "SSH to llm02"
  value       = var.llm02_deployed ? "ssh ${var.admin_username}@${azurerm_public_ip.llm02[0].ip_address}" : null
}

output "llm02_fqdn" {
  description = "llm02 FQDN"
  value       = var.llm02_deployed ? azurerm_public_ip.llm02[0].fqdn : null
}

###############################################################################
# llm03 — PersonaPlex speech-to-speech
###############################################################################

output "llm03_public_ip" {
  description = "llm03 public IP"
  value       = var.llm03_deployed ? azurerm_public_ip.llm03[0].ip_address : null
}

output "llm03_private_ip" {
  description = "llm03 private IP (for VNet access)"
  value       = var.llm03_deployed ? azurerm_network_interface.llm03[0].private_ip_address : null
}

output "llm03_ssh" {
  description = "SSH to llm03"
  value       = var.llm03_deployed ? "ssh ${var.admin_username}@${azurerm_public_ip.llm03[0].ip_address}" : null
}

output "llm03_fqdn" {
  description = "llm03 FQDN"
  value       = var.llm03_deployed ? azurerm_public_ip.llm03[0].fqdn : null
}

output "personaplex_endpoint" {
  description = "PersonaPlex WebSocket endpoint"
  value       = var.llm03_deployed ? "ws://${azurerm_public_ip.llm03[0].fqdn}:${var.llm03_port}" : null
}

###############################################################################
# Workstation VM
###############################################################################

output "workstation_public_ip" {
  description = "Workstation VM public IP"
  value       = var.workstation_deployed ? azurerm_public_ip.workstation[0].ip_address : null
}

output "workstation_ssh" {
  description = "SSH to Workstation VM"
  value       = var.workstation_deployed ? "ssh ${var.admin_username}@${azurerm_public_ip.workstation[0].ip_address}" : null
}

output "workstation_fqdn" {
  description = "Workstation VM FQDN"
  value       = var.workstation_deployed ? azurerm_public_ip.workstation[0].fqdn : null
}

###############################################################################
# Service endpoints (abstract names, from workstation via private IPs)
###############################################################################

output "vllm_large_llm_endpoint" {
  description = "Large LLM vLLM API endpoint"
  value       = var.llm01_deployed ? "http://${azurerm_network_interface.llm01[0].private_ip_address}:${var.vllm_port}/v1" : null
}

output "vllm_small_llm_endpoint" {
  description = "Small LLM vLLM API endpoint"
  value       = var.llm02_deployed ? "http://${azurerm_network_interface.llm02[0].private_ip_address}:${var.small_llm_port}/v1" : null
}

output "vllm_vision_llm_endpoint" {
  description = "Vision LLM vLLM API endpoint"
  value       = var.llm02_deployed ? "http://${azurerm_network_interface.llm02[0].private_ip_address}:${var.vision_llm_port}/v1" : null
}

output "vllm_medium_llm_endpoint" {
  description = "Medium LLM vLLM API endpoint"
  value       = var.llm02_deployed ? "http://${azurerm_network_interface.llm02[0].private_ip_address}:${var.medium_llm_port}/v1" : null
}

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.this.name
}
