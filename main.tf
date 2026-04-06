terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

locals {
  subnet_cidr = "10.0.0.0/24"
}

###############################################################################
# Shared networking
###############################################################################

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "this" {
  name                = "llm-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_subnet" "this" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnet_cidr]
}

###############################################################################
# Gemma VM — 4x A100 80GB, Gemma 4 31B, TP=4, 256K context
###############################################################################

resource "azurerm_network_security_group" "gemma" {
  name                = "gemma-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVLLMFromSubnet"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.vllm_port)
    source_address_prefix      = local.subnet_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "gemma" {
  name                = "gemma-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.gemma_zone != "" ? [var.gemma_zone] : []
  domain_name_label   = "gemma-llm"
}

resource "azurerm_network_interface" "gemma" {
  name                = "gemma-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.0.10"
    public_ip_address_id          = azurerm_public_ip.gemma.id
  }
}

resource "azurerm_network_interface_security_group_association" "gemma" {
  network_interface_id      = azurerm_network_interface.gemma.id
  network_security_group_id = azurerm_network_security_group.gemma.id
}

resource "azurerm_linux_virtual_machine" "gemma" {
  name                            = "gemma-vm"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.gemma_vm_size
  zone                            = var.gemma_zone != "" ? var.gemma_zone : null
  admin_username                  = var.admin_username
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.gemma.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.gemma_disk_size
  }

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-gemma.yaml", {
    admin_username        = var.admin_username
    hf_token              = var.hf_token
    model_id              = var.gemma_model_id
    served_name           = var.gemma_served_name
    max_model_len         = var.gemma_max_model_len
    gpu_memory_utilization = var.gemma_gpu_memory_utilization
    tool_call_parser      = var.gemma_tool_call_parser
    tp_size               = var.gemma_tp_size
    vllm_port             = var.vllm_port
  }))
}

###############################################################################
# Phi VM — 1x A100 80GB, Phi-4-mini, TP=1, GitHub operations sub-agent
###############################################################################

resource "azurerm_network_security_group" "phi" {
  name                = "phi-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowPhiVLLMFromSubnet"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.phi_port)
    source_address_prefix      = local.subnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowQwenVLFromSubnet"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.qwen_vl_port)
    source_address_prefix      = local.subnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowXLAMFromSubnet"
    priority                   = 1030
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.xlam_port)
    source_address_prefix      = local.subnet_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "phi" {
  name                = "phi-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.phi_zone != "" ? [var.phi_zone] : []
  domain_name_label   = "phi-llm"
}

resource "azurerm_network_interface" "phi" {
  name                = "phi-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.0.11"
    public_ip_address_id          = azurerm_public_ip.phi.id
  }
}

resource "azurerm_network_interface_security_group_association" "phi" {
  network_interface_id      = azurerm_network_interface.phi.id
  network_security_group_id = azurerm_network_security_group.phi.id
}

resource "azurerm_linux_virtual_machine" "phi" {
  name                            = "phi-vm"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.phi_vm_size
  zone                            = var.phi_zone != "" ? var.phi_zone : null
  admin_username                  = var.admin_username
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.phi.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.phi_disk_size
  }

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-phi.yaml", {
    admin_username             = var.admin_username
    hf_token                   = var.hf_token
    phi_model_id               = var.phi_model_id
    phi_served_name            = var.phi_served_name
    phi_max_model_len          = var.phi_max_model_len
    phi_gpu_memory_utilization = var.phi_gpu_memory_utilization
    phi_tool_call_parser       = var.phi_tool_call_parser
    phi_port                   = var.phi_port
    qwen_vl_model_id               = var.qwen_vl_model_id
    qwen_vl_served_name            = var.qwen_vl_served_name
    qwen_vl_max_model_len          = var.qwen_vl_max_model_len
    qwen_vl_gpu_memory_utilization = var.qwen_vl_gpu_memory_utilization
    qwen_vl_port                   = var.qwen_vl_port
    xlam_model_id               = var.xlam_model_id
    xlam_served_name            = var.xlam_served_name
    xlam_max_model_len          = var.xlam_max_model_len
    xlam_gpu_memory_utilization = var.xlam_gpu_memory_utilization
    xlam_port                   = var.xlam_port
  }))
}

###############################################################################
# Workstation VM — developer tools, T4 for Chrome/Playwright
###############################################################################

resource "azurerm_network_security_group" "workstation" {
  name                = "workstation-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "workstation" {
  name                = "workstation-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.workstation_zone != "" ? [var.workstation_zone] : []
  domain_name_label   = "llm-workstation"
}

resource "azurerm_network_interface" "workstation" {
  name                = "workstation-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.0.12"
    public_ip_address_id          = azurerm_public_ip.workstation.id
  }
}

resource "azurerm_network_interface_security_group_association" "workstation" {
  network_interface_id      = azurerm_network_interface.workstation.id
  network_security_group_id = azurerm_network_security_group.workstation.id
}

resource "azurerm_linux_virtual_machine" "workstation" {
  name                            = "workstation-vm"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.workstation_vm_size
  zone                            = var.workstation_zone != "" ? var.workstation_zone : null
  admin_username                  = var.admin_username
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.workstation.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.workstation_disk_size
  }

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-workstation.yaml", {
    admin_username   = var.admin_username
    hf_token         = var.hf_token
    gemma_ip         = "10.0.0.10"
    gemma_port       = var.vllm_port
    gemma_served_name = var.gemma_served_name
    gemma_max_model_len = var.gemma_max_model_len
    phi_ip              = "10.0.0.11"
    phi_port            = var.phi_port
    phi_served_name     = var.phi_served_name
    phi_max_model_len   = var.phi_max_model_len
    qwen_vl_ip          = "10.0.0.11"
    qwen_vl_port        = var.qwen_vl_port
    qwen_vl_served_name = var.qwen_vl_served_name
    qwen_vl_max_model_len = var.qwen_vl_max_model_len
    xlam_ip             = "10.0.0.11"
    xlam_port           = var.xlam_port
    xlam_served_name    = var.xlam_served_name
    xlam_max_model_len  = var.xlam_max_model_len
  }))
}
