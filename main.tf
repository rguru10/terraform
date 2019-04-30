provider "azurerm" {
    subscription_id = "45df0239-f686-4964-b033-c7ca354e0d48"
}

# generate random project name
resource "random_id" "project_name" {
  byte_length = 4
}

# Azure Resources
resource "azurerm_resource_group" "main" {
  name     = "${random_id.project_name.hex}-ratna-rg"
  location = "westus"
}

resource "azurerm_virtual_network" "main" {
  name                = "${random_id.project_name.hex}-vnet"
  resource_group_name = "${azurerm_resource_group.main.name}"
  location            = "${azurerm_resource_group.main.location}"
  address_space       = ["10.0.0.0/16"]
}