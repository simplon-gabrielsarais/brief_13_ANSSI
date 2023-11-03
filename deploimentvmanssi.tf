terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.75.0"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

resource "azurerm_resource_group" "RGGS" {
  name     = "GS-resources"
  location = "West Europe"
}

resource "azurerm_virtual_network" "RGVN" {
  name                = "GS-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.RGGS.location
  resource_group_name = azurerm_resource_group.RGGS.name
}

resource "azurerm_subnet" "GSSUB" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.RGGS.name
  virtual_network_name = azurerm_virtual_network.RGVN.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "example" {
  name                    = "GS-pubip"
  location                = azurerm_resource_group.RGGS.location
  resource_group_name     = azurerm_resource_group.RGGS.name
  allocation_method       = "Static"
  idle_timeout_in_minutes = 30
  
}

resource "azurerm_network_interface" "GSNETINT" {
  name                = "example-nic"
  location            = azurerm_resource_group.RGGS.location
  resource_group_name = azurerm_resource_group.RGGS.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.GSSUB.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.example.id
  }
}

resource "azurerm_network_security_group" "GSNSG" {
  name                = "NSG_GS"
  location            = azurerm_resource_group.RGGS.location
  resource_group_name = azurerm_resource_group.RGGS.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                        = "http-rule"
    priority                    = 1002
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "Tcp"
    source_port_range           = "*"
    destination_port_range      = "80"
    source_address_prefix       = "*"
    destination_address_prefix  = "*"
    }

  security_rule {
    name                        = "https-rule"
    priority                    = 1003
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "Tcp"
    source_port_range           = "*"
    destination_port_range      = "443"
    source_address_prefix       = "*"
    destination_address_prefix  = "*"
    }
}

resource "azurerm_linux_virtual_machine" "GSVM" {
  name                = "anssi-machine"
  resource_group_name = azurerm_resource_group.RGGS.name
  location            = azurerm_resource_group.RGGS.location
  size                = "Standard_Ds1_v2"
  admin_username      = "gabriel"
  network_interface_ids = [
    azurerm_network_interface.GSNETINT.id,

  ]

  admin_ssh_key {
    username   = "gabriel"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "8-lvm-gen2"
    version   = "latest"
  }
  provisioner "local-exec" {
    command = <<-EOT
              ansible-galaxy install -r requirements.yml
              sed -E -i 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/${azurerm_public_ip.example.ip_address}/g' inventory.ini
              ansible-playbook playbook.yml -i inventory.ini
    EOT
    working_dir = "/home/gabriel/Documents/brief_13_ANSSI/ansible"
  }
}
