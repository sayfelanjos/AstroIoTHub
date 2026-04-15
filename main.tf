terraform {
  required_version = ">= 1.2.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.68.0" # Atenção: Verifique se a v4.x já está estável para estes recursos
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_id" "storage_suffix" {
  byte_length = 4
}

# --- GRUPO DE RECURSOS ---
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# --- IOT HUB ---
resource "azurerm_iothub" "hub" {
  name                = var.iothub_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku {
    name     = var.iothub_sku
    capacity = var.iothub_units
  }
}

# --- STORAGE ---
resource "azurerm_storage_account" "storage" {
  name                     = "astro${random_id.storage_suffix.hex}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "telemetry" {
  name                  = var.storage_container_name
  storage_account_id  = azurerm_storage_account.storage.id
  container_access_type = "private"
}

# --- STREAM ANALYTICS JOB ---
resource "azurerm_stream_analytics_job" "stream_job" {
  name                = var.stream_job_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  streaming_units     = 1

  compatibility_level  = "1.2"
  output_error_policy  = "Stop"
  
  # Ajustado para bater com os nomes dos inputs/outputs abaixo
  transformation_query = <<QUERY
    SELECT * INTO [AstroBlobOutput] 
    FROM [AstroIoTHubInput] 
    TIMESTAMP BY EventEnqueuedUtcTime
QUERY
}

# --- INPUT (IOT HUB) ---
resource "azurerm_stream_analytics_stream_input_iothub" "input" {
  name                         = "AstroIoTHubInput"
  stream_analytics_job_name    = azurerm_stream_analytics_job.stream_job.name
  resource_group_name          = azurerm_resource_group.rg.name
  endpoint                     = "messages/events"
  eventhub_consumer_group_name = "$Default"
  
  # Referenciando o recurso criado dinamicamente
  iothub_namespace             = azurerm_iothub.hub.name
  shared_access_policy_key     = azurerm_iothub.hub.shared_access_policy[0].primary_key
  shared_access_policy_name    = "iothubowner"

  serialization {
    type   = "Json"
    encoding = "UTF8"
  }
}

# --- OUTPUT (BLOB) ---
resource "azurerm_stream_analytics_output_blob" "output" {
  name                      = "AstroBlobOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.stream_job.name
  resource_group_name       = azurerm_resource_group.rg.name
  
  # Referenciando o storage criado dinamicamente
  storage_account_name      = azurerm_storage_account.storage.name
  storage_account_key       = azurerm_storage_account.storage.primary_access_key
  storage_container_name    = azurerm_storage_container.telemetry.name
  
  path_pattern              = "ano={datetime:yyyy}/mes={datetime:MM}/dia={datetime:dd}"
  date_format               = "yyyy-MM-dd"
  time_format               = "HH"

  serialization {
      type   = "Json"
      encoding = "UTF8"
      format   = "LineSeparated"
  }
}


resource "null_resource" "create_iot_device" {
  depends_on = [azurerm_iothub.hub]

  provisioner "local-exec" {
    # Usamos uma linha única para evitar problemas de escape no shell do Terraform
    command = "az extension add --name azure-iot --yes && az iot hub device-identity create --device-id 'RaspberryPiAstro' --hub-name ${azurerm_iothub.hub.name} --resource-group ${azurerm_resource_group.rg.name} --auth-method shared_private_key"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "az iot hub device-identity delete --device-id 'RaspberryPiAstro' --hub-name ${self.triggers.hub_name} --resource-group ${self.triggers.rg_name}"
  }

  triggers = {
    hub_name = azurerm_iothub.hub.name
    rg_name  = azurerm_resource_group.rg.name
  }
}

resource "azurerm_dashboard_grafana" "astro_dashboard" {
  name                              = "astro-grafana-${random_id.storage_suffix.hex}"
  resource_group_name               = azurerm_resource_group.rg.name
  location                          = azurerm_resource_group.rg.location
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = false
  public_network_access_enabled     = true
  grafana_major_version = "12"

  identity {
    type = "SystemAssigned"
  }
}

# Permissão para o Grafana ler os dados do Azure Monitor/Storage
resource "azurerm_role_assignment" "grafana_monitor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.astro_dashboard.identity[0].principal_id
}

resource "azurerm_log_analytics_workspace" "astro_law" {
  name                = "astro-law-${random_id.storage_suffix.hex}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30 # Para o seu plano de 2 meses, podemos ajustar aqui
}

# 2. Configurar o Grafana para ter permissão de ler este Workspace
resource "azurerm_role_assignment" "grafana_la_reader" {
  scope                = azurerm_log_analytics_workspace.astro_law.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_dashboard_grafana.astro_dashboard.identity[0].principal_id
}
