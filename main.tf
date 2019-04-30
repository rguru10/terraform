provider "azurerm" {
    subscription_id = "45df0239-f686-4964-b033-c7ca354e0d48"
}

# generate random project name
resource "random_id" "project_name" {
  byte_length = 4
}

# generate sql password
resource "random_id" "sql_password" {
  byte_length = 32
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

# Data Sources
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "subscription" {}

data "azurerm_role_definition" "role_definition" {
  name = "Contributor"
}

data "template_file" "setup" {
  template = "${file("setupvault.tpl")}"

  vars {
    vault_url             = "${var.vault_url}"
  }
}

# Service Principal Module
module "vaultapp" {
  source             = "./modules/service_principal"
  resource_group     = "${azurerm_resource_group.main.id}"
  location           = "${azurerm_resource_group.main.location}"
  project_name       = "${random_id.project_name.hex}"
  subscription_id    = "${data.azurerm_client_config.current.subscription_id}"
  role_definition_id = "${data.azurerm_role_definition.role_definition.id}"
}

resource "azurerm_virtual_machine" "main" {
  name                          = "${random_id.project_name.hex}-vm"
  location                      = "${azurerm_resource_group.main.location}"
  resource_group_name           = "${azurerm_resource_group.main.name}"
  network_interface_ids         = ["${azurerm_network_interface.main.id}"]
  vm_size                       = "Standard_A2_v2"
  delete_os_disk_on_termination = true

  identity = {
    type = "SystemAssigned"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${random_id.project_name.hex}vm-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${random_id.project_name.hex}vm"
    admin_username = "ubuntu"
    admin_password = "Password1234!"
    custom_data    = "${data.template_file.setup.rendered}"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}

resource "azurerm_virtual_machine_extension" "virtual_machine_extension" {
  name                 = "vault"
  location             = "${var.location}"
  resource_group_name  = "${azurerm_resource_group.main.name}"
  virtual_machine_name = "${azurerm_virtual_machine.main.name}"
  publisher            = "Microsoft.ManagedIdentity"
  type                 = "ManagedIdentityExtensionForLinux"
  type_handler_version = "1.0"

  settings = <<SETTINGS
    {
        "port": 50342
    }
SETTINGS
}

resource "azurerm_mysql_server" "sql" {
  name                         = "${random_id.project_name.hex}-mysql"
  resource_group_name          = "${azurerm_resource_group.main.name}"
  location                     = "${azurerm_resource_group.main.location}"

  sku {
    name     = "B_Gen5_2"
    capacity = 2
    tier     = "Basic"
    family   = "Gen5"
  }

  storage_profile {
    storage_mb            = 5120
    backup_retention_days = 7
    geo_redundant_backup  = "Disabled"
  }

  administrator_login          = "sqladmin"
  administrator_login_password = "${random_id.sql_password.id}"
  version                      = "5.7"
  ssl_enforcement              = "Disabled"
}

resource "azurerm_mysql_database" "database" {
  name                = "exampledb"
  resource_group_name = "${azurerm_resource_group.main.name}"
  server_name         = "${azurerm_mysql_server.sql.name}"
  charset             = "utf8"
  collation           = "utf8_general_ci"
}

resource "azurerm_mysql_firewall_rule" "sql" {
  name                = "FirewallRule1"
  resource_group_name = "${azurerm_resource_group.main.name}"
  server_name         = "${azurerm_mysql_server.sql.name}"
  start_ip_address    = "${azurerm_public_ip.main.ip_address}"
  end_ip_address      = "${azurerm_public_ip.main.ip_address}"
}