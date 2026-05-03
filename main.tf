# 1. Configuração do Provider
provider "azurerm" {
  features {}
}

# 2. Grupo de Recursos
resource "azurerm_resource_group" "astro_rg" {
  name     = "Astro-Econ-RG"
  location = "East US"
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

# 4. Endereço IP Público com DNS Label
resource "azurerm_public_ip" "pip" {
  name                = "astro-vm-ip"
  resource_group_name = azurerm_resource_group.astro_rg.name
  location            = azurerm_resource_group.astro_rg.location
  sku                 = "Standard"
  allocation_method   = "Static"
  # This creates: astro-magnetometer.eastus.cloudapp.azure.com
  domain_name_label   = "astro-magnetometer" 
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
    name                       = "HTTP-Certbot-Challenge"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
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

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# 7. Máquina Virtual com Let's Encrypt (Certbot) e Auto-Mount
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "Astro-Server-VM"
  resource_group_name = azurerm_resource_group.astro_rg.name
  location            = azurerm_resource_group.astro_rg.location
  size                = "Standard_B1ms"
  admin_username      = "astroadmin"
  network_interface_ids = [azurerm_network_interface.nic.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              # 1. Mount Persistent Disk (LUN 10)
              DISK_DEVICE="/dev/disk/azure/scsi1/lun10"
              MOUNT_POINT="/mnt/astro_data"
              
              mkdir -p $MOUNT_POINT
              # Only format if no filesystem exists (Safe for data preservation)
              if ! blkid $DISK_DEVICE; then
                  mkfs.ext4 $DISK_DEVICE
              fi
              
              mount $DISK_DEVICE $MOUNT_POINT
              echo "$DISK_DEVICE $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab

              # 2. Install Nginx and Certbot
              apt-get update
              apt-get install -y nginx certbot python3-certbot-nginx

              # 3. Create Nginx config for your Azure DNS
              cat <<EOT > /etc/nginx/sites-available/default
              server {
                  listen 80;
                  server_name astro-magnetometer.eastus.cloudapp.azure.com;

                  location / {
                      proxy_pass http://localhost:3000;
                      proxy_set_header Host \$host;
                      proxy_set_header X-Real-IP \$remote_addr;
                  }

                  location /influx/ {
                      proxy_pass http://localhost:8086/;
                      proxy_set_header Host \$host;
                      proxy_set_header X-Real-IP \$remote_addr;
                  }
              }
              EOT

              systemctl restart nginx

              # 4. Request Let's Encrypt Cert (Non-Interactive)
              # Note: This requires the DNS to be active. 
              # It may take a minute for Azure DNS to propagate after creation.
              certbot --nginx -d astro-magnetometer.eastus.cloudapp.azure.com --non-interactive --agree-tos -m admin@example.com --redirect
              EOF
  )

  admin_ssh_key {
    username   = "astroadmin"
    public_key = file("~/.ssh/id_rsa.pub")
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

# 8. Disco de Dados Persistente
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