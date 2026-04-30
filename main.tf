# 1. Configuração do Provider
provider "azurerm" {
  features {}
}

# 2. Grupo de Recursos
resource "azurerm_resource_group" "astro_rg" {
  name     = "Astro-Econ-RG"
  location = "East US" # Pode alterar para a região da sua preferência
}

# 3. Infraestrutura de Rede
resource "azurerm_virtual_network" "vnet" {
  name                = "astro-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.astro_rg.location
  resource_group_name = azurerm_resource_group.astro_rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.astro_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# 4. Endereço IP Público (para aceder ao Grafana)
resource "azurerm_public_ip" "pip" {
  name                = "astro-vm-ip"
  resource_group_name = azurerm_resource_group.astro_rg.name
  location            = azurerm_resource_group.astro_rg.location
  sku               = "Standard"
  allocation_method = "Static"
}

# 5. Segurança (Firewall - NSG)
resource "azurerm_network_security_group" "nsg" {
  name                = "astro-nsg"
  location            = azurerm_resource_group.astro_rg.location
  resource_group_name = azurerm_resource_group.astro_rg.name

  security_rule {
    name                       = "SSH"
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
    name                       = "Grafana"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "MQTT"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1883"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# 6. Interface de Rede
resource "azurerm_network_interface" "nic" {
  name                = "astro-nic"
  location            = azurerm_resource_group.astro_rg.location
  resource_group_name = azurerm_resource_group.astro_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# 7. Máquina Virtual (Standard_B1ms - 2GB RAM / Económica)
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "Astro-Server-VM"
  resource_group_name = azurerm_resource_group.astro_rg.name
  location            = azurerm_resource_group.astro_rg.location
  size                = "Standard_B1ms"
  admin_username      = "astroadmin"
  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = "astroadmin"
    public_key = file("~/.ssh/id_rsa.pub") # Certifique-se de que tem a sua chave pública aqui
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# 8. DISCO DE DADOS PERSISTENTE (Onde os dados do Astro serão guardados)
resource "azurerm_managed_disk" "data_disk" {
  name                 = "Astro-Data-Disk"
  location             = azurerm_resource_group.astro_rg.location
  resource_group_name  = azurerm_resource_group.astro_rg.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
}

# 9. Anexar o Disco à VM
resource "azurerm_virtual_machine_data_disk_attachment" "attach" {
  managed_disk_id    = azurerm_managed_disk.data_disk.id
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  lun                = "10"
  caching            = "ReadWrite"
}

