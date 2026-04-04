variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "r-mordaseiwicz-xcsh"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralus"
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "gpu-llm-vm"
}

variable "vm_size" {
  description = "Size of the VM. Standard_NC24s_v3 = 4x V100 (64GB VRAM) for 70B models"
  type        = string
  default     = "Standard_NC24s_v3"

  validation {
    condition = contains([
      "Standard_NC6s_v3",
      "Standard_NC12s_v3",
      "Standard_NC24s_v3",
      "Standard_NC4as_T4_v3",
      "Standard_NC8as_T4_v3",
      "Standard_NC16as_T4_v3",
    ], var.vm_size)
    error_message = "Must be a GPU VM size available in centralus."
  }
}

variable "zone" {
  description = "Availability zone (centralus supports 1 and 3 for NCSv3)"
  type        = string
  default     = "1"

  validation {
    condition     = contains(["1", "3"], var.zone)
    error_message = "Central US supports zones 1 and 3 for NCSv3."
  }
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB. 256GB recommended for model weights."
  type        = number
  default     = 256
}
