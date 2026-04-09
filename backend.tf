terraform {
  backend "azurerm" {
    resource_group_name  = "r-mordaseiwicz-xcsh"
    storage_account_name = "tfstatemordaseiwicz"
    container_name       = "tfstate"
    key                  = "azure-llm.tfstate"
  }
}
