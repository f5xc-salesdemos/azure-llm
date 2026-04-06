resource_group_name = "r-mordaseiwicz-xcsh"
location            = "centralus"
admin_username      = "azureuser"
ssh_public_key_path = "~/.ssh/id_rsa.pub"

# Gemma VM — 4x A100 80GB, 256K context
gemma_vm_size       = "Standard_NC96ads_A100_v4"
gemma_zone          = "2"
gemma_disk_size     = 256

# Phi VM — 4x A100 80GB (Phi+Qwen GPU 0, xLAM GPU 1, Qwen3 GPU 2)
phi_vm_size         = "Standard_NC96ads_A100_v4"
phi_zone            = "2"

# Workstation — T4 for Chrome/Playwright (pending T4 quota)
workstation_vm_size = "Standard_NC8as_T4_v3"
workstation_zone    = "2"
