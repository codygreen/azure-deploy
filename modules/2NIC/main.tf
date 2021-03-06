data "azurerm_resource_group" "bigiprg" {
  name = var.resource_group_name
}

# Create a Public IP for bigip
resource "azurerm_public_ip" "mgmt_public_ip" {
  name                = "${var.dnsLabel}-mgmt-pip"
  location            = data.azurerm_resource_group.bigiprg.location
  resource_group_name = data.azurerm_resource_group.bigiprg.name
  allocation_method   = var.allocation_method
  domain_name_label   = var.dnsLabel
  tags = {
    Name   = "${var.dnsLabel}-mgmt-pip"
    owner  = var.dnsLabel
    source = "terraform"
  }
}

#Create Mgmt interface for BIG-IP
resource "azurerm_network_interface" "mgmt_nic" {
  name                = "${var.dnsLabel}-mgmt-nic"
  location            = data.azurerm_resource_group.bigiprg.location
  resource_group_name = data.azurerm_resource_group.bigiprg.name

  ip_configuration {
    name                          = "${var.dnsLabel}-mgmt"
    primary                       = true
    subnet_id                     = var.vnet_subnet_id[0]
    private_ip_address_allocation = var.allocation_method
    public_ip_address_id          = azurerm_public_ip.mgmt_public_ip.id
  }
  tags = {
    owner  = var.dnsLabel
    Name   = "${var.dnsLabel}-mgmt-nic"
    source = "terraform"
  }
}

#Create Securitygroup for BIG-IP mgmt interface
resource "azurerm_network_security_group" "bigip_sg" {
  name                = "${var.dnsLabel}-mgmt-nsg"
  resource_group_name = data.azurerm_resource_group.bigiprg.name
  location            = data.azurerm_resource_group.bigiprg.location
  security_rule {
    name                       = "allow_SSH"
    description                = "Allow SSH access"
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
    name                       = "mgmt_allow_HTTPS"
    description                = "Allow HTTPS access"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = {
    owner  = var.dnsLabel
    Name   = "${var.dnsLabel}-bigip_sg"
    source = "terraform"
  }
}

#Attach Securitygroup to Mgmt Interface
resource "azurerm_network_interface_security_group_association" "mgmtnicnsg" {
  network_interface_id      = azurerm_network_interface.mgmt_nic.id
  network_security_group_id = azurerm_network_security_group.bigip_sg.id
}

# Create a Public IP for Ext Interfaces on bigip
resource "azurerm_public_ip" "ext_public_ip" {
  name                = "${var.dnsLabel}-ext-pip"
  location            = data.azurerm_resource_group.bigiprg.location
  resource_group_name = data.azurerm_resource_group.bigiprg.name
  allocation_method   = var.allocation_method

  tags = {
    Name   = "${var.dnsLabel}-ext"
    owner  = var.dnsLabel
    source = "terraform"
  }
}

# Create the ext-nic interface for BIG-IP
resource "azurerm_network_interface" "ext_nic" {
  name                          = "${var.dnsLabel}-ext-nic"
  location                      = data.azurerm_resource_group.bigiprg.location
  resource_group_name           = data.azurerm_resource_group.bigiprg.name
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "${var.dnsLabel}-extip"
    subnet_id                     = var.vnet_subnet_id[1]
    private_ip_address_allocation = var.allocation_method
    public_ip_address_id          = azurerm_public_ip.ext_public_ip.id
  }
  tags = {
    owner  = var.dnsLabel
    Name   = "${var.dnsLabel}-ext-nic"
    source = "terraform"
  }
}

#Create Securitygroup for BIG-IP Ext interface
resource "azurerm_network_security_group" "bigip_extnic_nsg" {
  name                = "${var.dnsLabel}-nsg"
  resource_group_name = data.azurerm_resource_group.bigiprg.name
  location            = data.azurerm_resource_group.bigiprg.location
  tags = {
    owner  = var.dnsLabel
    Name   = "${var.dnsLabel}-bigip_extnic_nsg"
    source = "terraform"
  }
}

#Attach Securitygroup to Ext Interface
resource "azurerm_network_interface_security_group_association" "extnicnsg" {
  network_interface_id      = azurerm_network_interface.ext_nic.id
  network_security_group_id = azurerm_network_security_group.bigip_extnic_nsg.id
}

# Create F5 BIGIP VM
resource "azurerm_virtual_machine" "f5vm01" {
  name                         = "${var.dnsLabel}-f5vm01"
  location                     = data.azurerm_resource_group.bigiprg.location
  resource_group_name          = data.azurerm_resource_group.bigiprg.name
  primary_network_interface_id = azurerm_network_interface.mgmt_nic.id
  network_interface_ids        = [azurerm_network_interface.mgmt_nic.id, azurerm_network_interface.ext_nic.id]
  vm_size                      = var.f5_instance_type

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true


  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "f5-networks"
    offer     = var.f5_product_name
    sku       = var.f5_image_name
    version   = var.f5_version
  }

  storage_os_disk {
    name              = "osdisk-${var.dnsLabel}-f5vm01"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = var.storage_account_type
  }

  os_profile {
    computer_name  = "${var.dnsLabel}-f5vm01"
    admin_username = var.f5_username
    admin_password = var.ADMIN_PASSWD
    #custom_data    = data.template_file.f5_bigip_onboard.rendered
  }
  os_profile_linux_config {
    disable_password_authentication = var.enable_ssh_key

    dynamic ssh_keys {
      for_each = var.enable_ssh_key ? [var.f5_ssh_publickey] : []
      content {
        path     = "/home/${var.f5_username}/.ssh/authorized_keys"
        key_data = file(var.f5_ssh_publickey)
      }
    }
  }
  plan {
    name      = var.f5_image_name
    publisher = "f5-networks"
    product   = var.f5_product_name
  }
  tags = {
    owner  = var.dnsLabel
    Name   = "${var.dnsLabel}-f5vm01"
    source = "terraform"
  }
}

data "azurerm_public_ip" "f5vm01mgmtpip" {
  name                = azurerm_public_ip.mgmt_public_ip.name
  resource_group_name = data.azurerm_resource_group.bigiprg.name
  depends_on          = [azurerm_virtual_machine.f5vm01]
}
