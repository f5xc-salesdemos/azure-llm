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
# llm01 — Large LLM server (4x A100 80GB, TP=4, 256K context)
###############################################################################

resource "azurerm_network_security_group" "llm01" {
  count               = var.llm01_deployed ? 1 : 0
  name                = "llm01-nsg"
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

resource "azurerm_public_ip" "llm01" {
  count               = var.llm01_deployed ? 1 : 0
  name                = "llm01-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.llm01_zone != "" ? [var.llm01_zone] : []
  domain_name_label   = "llm01"
}

resource "azurerm_network_interface" "llm01" {
  count               = var.llm01_deployed ? 1 : 0
  name                = "llm01-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.0.10"
    public_ip_address_id          = azurerm_public_ip.llm01[0].id
  }
}

resource "azurerm_network_interface_security_group_association" "llm01" {
  count                     = var.llm01_deployed ? 1 : 0
  network_interface_id      = azurerm_network_interface.llm01[0].id
  network_security_group_id = azurerm_network_security_group.llm01[0].id
}

resource "azurerm_linux_virtual_machine" "llm01" {
  count                           = var.llm01_deployed ? 1 : 0
  name                            = "llm01"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.llm01_vm_size
  zone                            = var.llm01_zone != "" ? var.llm01_zone : null
  admin_username                  = var.admin_username
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.llm01[0].id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.llm01_disk_size
  }

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-llm01.yaml", {
    admin_username         = var.admin_username
    hf_token               = var.hf_token
    model_id               = var.llm01_model_id
    served_name            = var.llm01_served_name
    max_model_len          = var.llm01_max_model_len
    gpu_memory_utilization = var.llm01_gpu_memory_utilization
    tool_call_parser       = var.llm01_tool_call_parser
    reasoning_parser       = var.llm01_reasoning_parser
    hf_overrides           = var.llm01_hf_overrides
    allow_long_context     = var.llm01_allow_long_context
    extra_served_names     = var.llm01_extra_served_names
    tp_size                = var.llm01_tp_size
    vllm_port              = var.vllm_port
  }))
}

###############################################################################
# llm02 — Small/Medium/Vision LLM server (4x A100 80GB, 3 models)
###############################################################################

resource "azurerm_network_security_group" "llm02" {
  count               = var.llm02_deployed ? 1 : 0
  name                = "llm02-nsg"
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
    name                       = "AllowSmallLLMFromSubnet"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.small_llm_port)
    source_address_prefix      = local.subnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVisionLLMFromSubnet"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.vision_llm_port)
    source_address_prefix      = local.subnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowMediumLLMFromSubnet"
    priority                   = 1030
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.medium_llm_port)
    source_address_prefix      = local.subnet_cidr
    destination_address_prefix = "*"
  }

}

resource "azurerm_public_ip" "llm02" {
  count               = var.llm02_deployed ? 1 : 0
  name                = "llm02-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.llm02_zone != "" ? [var.llm02_zone] : []
  domain_name_label   = "llm02"
}

resource "azurerm_network_interface" "llm02" {
  count               = var.llm02_deployed ? 1 : 0
  name                = "llm02-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.0.11"
    public_ip_address_id          = azurerm_public_ip.llm02[0].id
  }
}

resource "azurerm_network_interface_security_group_association" "llm02" {
  count                     = var.llm02_deployed ? 1 : 0
  network_interface_id      = azurerm_network_interface.llm02[0].id
  network_security_group_id = azurerm_network_security_group.llm02[0].id
}

resource "azurerm_linux_virtual_machine" "llm02" {
  count                           = var.llm02_deployed ? 1 : 0
  name                            = "llm02"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.llm02_vm_size
  zone                            = var.llm02_zone != "" ? var.llm02_zone : null
  admin_username                  = var.admin_username
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.llm02[0].id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.llm02_disk_size
  }

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-llm02.yaml", {
    admin_username                    = var.admin_username
    hf_token                          = var.hf_token
    small_llm_model_id                = var.small_llm_model_id
    small_llm_served_name             = var.small_llm_served_name
    small_llm_max_model_len           = var.small_llm_max_model_len
    small_llm_gpu_memory_utilization  = var.small_llm_gpu_memory_utilization
    small_llm_tool_call_parser        = var.small_llm_tool_call_parser
    small_llm_port                    = var.small_llm_port
    small_llm_cuda_devices            = var.small_llm_cuda_devices
    small_llm_speculative_model       = var.small_llm_speculative_model
    small_llm_num_speculative_tokens  = var.small_llm_num_speculative_tokens
    small_llm_ngram_prompt_lookup_min = var.small_llm_ngram_prompt_lookup_min
    small_llm_ngram_prompt_lookup_max = var.small_llm_ngram_prompt_lookup_max
    small_llm_enable_chunked_prefill  = var.small_llm_enable_chunked_prefill
    small_llm_vllm_compile_level      = var.small_llm_vllm_compile_level
    vision_llm_model_id               = var.vision_llm_model_id
    vision_llm_served_name            = var.vision_llm_served_name
    vision_llm_max_model_len          = var.vision_llm_max_model_len
    vision_llm_gpu_memory_utilization = var.vision_llm_gpu_memory_utilization
    vision_llm_port                   = var.vision_llm_port
    vision_llm_cuda_devices           = var.vision_llm_cuda_devices
    medium_llm_model_id               = var.medium_llm_model_id
    medium_llm_served_name            = var.medium_llm_served_name
    medium_llm_max_model_len          = var.medium_llm_max_model_len
    medium_llm_gpu_memory_utilization = var.medium_llm_gpu_memory_utilization
    medium_llm_port                   = var.medium_llm_port
    medium_llm_tp_size                = var.medium_llm_tp_size
    medium_llm_cuda_devices           = var.medium_llm_cuda_devices
  }))
}

###############################################################################
# llm03 — PersonaPlex speech-to-speech server (1x H100 NVL 94GB)
###############################################################################

resource "azurerm_network_security_group" "llm03" {
  count               = var.llm03_deployed ? 1 : 0
  name                = "llm03-nsg"
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
    name                       = "AllowPersonaPlex"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.llm03_port)
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "llm03" {
  count               = var.llm03_deployed ? 1 : 0
  name                = "llm03-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.llm03_zone != "" ? [var.llm03_zone] : []
  domain_name_label   = "llm03"
}

resource "azurerm_network_interface" "llm03" {
  count               = var.llm03_deployed ? 1 : 0
  name                = "llm03-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.0.13"
    public_ip_address_id          = azurerm_public_ip.llm03[0].id
  }
}

resource "azurerm_network_interface_security_group_association" "llm03" {
  count                     = var.llm03_deployed ? 1 : 0
  network_interface_id      = azurerm_network_interface.llm03[0].id
  network_security_group_id = azurerm_network_security_group.llm03[0].id
}

resource "azurerm_linux_virtual_machine" "llm03" {
  count                           = var.llm03_deployed ? 1 : 0
  name                            = "llm03"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.llm03_vm_size
  zone                            = var.llm03_zone != "" ? var.llm03_zone : null
  admin_username                  = var.admin_username
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.llm03[0].id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.llm03_disk_size
  }

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-llm03.yaml", {
    admin_username = var.admin_username
    hf_token       = var.hf_token
    model_id       = var.llm03_model_id
    server_port    = var.llm03_port
  }))
}

###############################################################################
# Workstation VM — developer tools, T4 for Chrome/Playwright
###############################################################################

resource "azurerm_network_security_group" "workstation" {
  count               = var.workstation_deployed ? 1 : 0
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
  count               = var.workstation_deployed ? 1 : 0
  name                = "workstation-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.workstation_zone != "" ? [var.workstation_zone] : []
  domain_name_label   = "xcsh"
}

resource "azurerm_network_interface" "workstation" {
  count               = var.workstation_deployed ? 1 : 0
  name                = "workstation-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.0.12"
    public_ip_address_id          = azurerm_public_ip.workstation[0].id
  }
}

resource "azurerm_network_interface_security_group_association" "workstation" {
  count                     = var.workstation_deployed ? 1 : 0
  network_interface_id      = azurerm_network_interface.workstation[0].id
  network_security_group_id = azurerm_network_security_group.workstation[0].id
}

resource "azurerm_linux_virtual_machine" "workstation" {
  count                           = var.workstation_deployed ? 1 : 0
  name                            = "xcsh"
  computer_name                   = "xcsh"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.workstation_vm_size
  zone                            = var.workstation_zone != "" ? var.workstation_zone : null
  admin_username                  = var.admin_username
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.workstation[0].id]

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
    admin_username      = var.admin_username
    hf_token            = var.hf_token
    large_llm_base_url  = var.llm01_deployed ? "http://${azurerm_network_interface.llm01[0].private_ip_address}:${var.vllm_port}/v1" : ""
    large_llm_model     = var.llm01_served_name
    large_llm_ctx       = var.llm01_max_model_len
    small_llm_base_url  = var.llm02_deployed ? "http://${azurerm_network_interface.llm02[0].private_ip_address}:${var.small_llm_port}/v1" : (var.llm01_deployed ? "http://${azurerm_network_interface.llm01[0].private_ip_address}:${var.vllm_port}/v1" : "")
    small_llm_model     = var.llm02_deployed ? var.small_llm_served_name : var.llm01_served_name
    small_llm_ctx       = var.llm02_deployed ? var.small_llm_max_model_len : var.llm01_max_model_len
    vision_llm_base_url = var.llm02_deployed ? "http://${azurerm_network_interface.llm02[0].private_ip_address}:${var.vision_llm_port}/v1" : (var.llm01_deployed ? "http://${azurerm_network_interface.llm01[0].private_ip_address}:${var.vllm_port}/v1" : "")
    vision_llm_model    = var.llm02_deployed ? var.vision_llm_served_name : var.llm01_served_name
    vision_llm_ctx      = var.llm02_deployed ? var.vision_llm_max_model_len : var.llm01_max_model_len
    medium_llm_base_url = var.llm02_deployed ? "http://${azurerm_network_interface.llm02[0].private_ip_address}:${var.medium_llm_port}/v1" : (var.llm01_deployed ? "http://${azurerm_network_interface.llm01[0].private_ip_address}:${var.vllm_port}/v1" : "")
    medium_llm_model    = var.llm02_deployed ? var.medium_llm_served_name : var.llm01_served_name
    medium_llm_ctx      = var.llm02_deployed ? var.medium_llm_max_model_len : var.llm01_max_model_len
  }))
}
