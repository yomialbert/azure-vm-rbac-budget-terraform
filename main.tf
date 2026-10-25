
# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

# +rg
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg-vm-rbac"
  location = var.location
  tags = {
    Project = "${var.prefix}-rbac"
  }
}

# +vnet +subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags = {
  Project    = "${var.prefix}-rbac"
  CostCenter = var.prefix
}
}
# +subnet
resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  address_prefixes     = ["10.0.1.0/24"]
  virtual_network_name = azurerm_virtual_network.vnet.name
  

}
# +NIC
resource "azurerm_network_interface" "nic" {
  name                = "${var.prefix}-nic"
  location            = azurerm_virtual_network.vnet.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic" #let azure assign the ip
  }
tags = {
  CostCenter = var.prefix
}
}

# +VM itself
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "${var.prefix}-vm"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = "Standard_B1s"
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic.id]
  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand("~/.ssh/azure_vsVm_rsa.pub")) # public key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference { # which OS image to boot
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
tags = {
  Project    = "${var.prefix}-rbac"
  CostCenter = var.prefix
}
}

# +custom role: this role allows user to read and restart vm and it only avaiable for vms
resource "azurerm_role_definition" "vm_restart" {
  description = "Read and restart this VM only"
  name        = "${var.prefix}-VM Restart Users"
  scope       = azurerm_linux_virtual_machine.vm.id
  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/restart/action"

    ]
    not_actions = []

  }
  assignable_scopes = [azurerm_linux_virtual_machine.vm.id]

}

# + assign the role to user or users
resource "azurerm_role_assignment" "vm_restart" {
    scope = azurerm_linux_virtual_machine.vm.id
    role_definition_id = azurerm_role_definition.vm_restart.role_definition_id
    principal_id = var.operator_object_id #assigned user entra object id
  
}

# Look up the built-in policy that requires a tag on resources
data "azurerm_policy_definition" "require_tag" {
  display_name = "Require a tag on resources"
}
# Assign it to the resource group: untagged resources get denied
resource "azurerm_resource_group_policy_assignment" "tags" {
  name                 = "require-costcenter"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = data.azurerm_policy_definition.require_tag.id
  parameters = jsonencode({ tagName = { value = "CostCenter" } }) # tag to enforce
}

# +BUDGET + ALERT WARNS (does not enforce) when spend crosses the threshold
resource "azurerm_consumption_budget_resource_group" "budget" {
    name = "${var.prefix}-budget"
    resource_group_id = azurerm_resource_group.rg.id
    amount = 10 # monthly
    time_grain = "Monthly"
    time_period {
      start_date = "2026-10-01T00:00:00Z" 
    }
    notification {
      enabled = true
      threshold = 80    # get email at 80% of GBP10 which is GBP8
      operator = "GreaterThanOrEqualTo"
      contact_emails = [var.email_alert]
    }
  
}