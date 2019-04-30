provider "azurerm" {
    subscription_id = "45df0239-f686-4964-b033-c7ca354e0d48"
}

# generate random project name
resource "random_id" "project_name" {
  byte_length = 4
}

# Local for tag to attach to all items
locals {
  tags = "${merge(var.tags, map("ProjectName", random_id.project_name.hex))}"
}

# Azure Resources
resource "azurerm_resource_group" "main" {
  name     = "${random_id.project_name.hex}-ratna-rg"
  location = "${var.location}"
  tags     = "${local.tags}"
}

resource "azurerm_virtual_network" "main" {
  name                = "${random_id.project_name.hex}-vnet"
  resource_group_name = "${azurerm_resource_group.main.name}"
  location            = "${azurerm_resource_group.main.location}"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "main" {
  count                = 3
  name                 = "${random_id.project_name.hex}-subnet-${count.index}"
  resource_group_name  = "${azurerm_resource_group.main.name}"
  virtual_network_name = "${azurerm_virtual_network.main.name}"
  address_prefix       = "10.0.${count.index+1}.0/24"
}

resource "azurerm_public_ip" "main" {
  name                         = "${random_id.project_name.hex}-pubip"
  location                     = "${azurerm_resource_group.main.location}"
  resource_group_name          = "${azurerm_resource_group.main.name}"
  allocation_method            = "Static"
}

resource "azurerm_network_interface" "main" {
  name                = "${random_id.project_name.hex}-nic"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  ip_configuration {
    name                          = "config1"
    subnet_id                     = "${azurerm_subnet.main.0.id}"
    public_ip_address_id          = "${azurerm_public_ip.main.id}"
    private_ip_address_allocation = "dynamic"
  }
}