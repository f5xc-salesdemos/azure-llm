resource_group_name = "r-mordaseiwicz-xcsh"
location            = "centralus"
admin_username      = "azureuser"
ssh_public_key_path = "~/.ssh/id_rsa.pub"

# Deploy toggles — set false to skip provisioning
llm01_deployed       = false
llm02_deployed       = false
llm03_deployed       = false
workstation_deployed = true

# llm01 — Large LLM (4x A100 80GB, 256K context)
llm01_vm_size   = "Standard_NC96ads_A100_v4"
llm01_zone      = "2"
llm01_disk_size = 256

# llm02 — Small/Medium/Vision LLM (4x A100 80GB, 3 models)
llm02_vm_size = "Standard_NC96ads_A100_v4"
llm02_zone    = "2"

# llm03 — PersonaPlex speech-to-speech (1x H100 NVL 94GB)
llm03_vm_size = "Standard_NC40ads_H100_v5"
llm03_zone    = ""

# Workstation — T4 for Chrome/Playwright (pending T4 quota)
workstation_vm_size = "Standard_NC8as_T4_v3"
workstation_zone    = "2"
