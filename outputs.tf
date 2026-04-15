output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "iothub_name" {
  value = azurerm_iothub.hub.name
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "storage_container_name" {
  value = azurerm_storage_container.telemetry.name
}

output "stream_analytics_job_name" {
  value = azurerm_stream_analytics_job.stream_job.name
}

data "external" "device_connection_string" {
  depends_on = [null_resource.create_iot_device]
  program = ["bash", "-c", "echo \"{\\\"cs\\\": \\\"$(az iot hub device-identity connection-string show --device-id 'RaspberryPiAstro' --hub-name ${azurerm_iothub.hub.name} --query connectionString -o tsv)\\\"}\""]
}

output "iot_device_connection_string" {
  value     = data.external.device_connection_string.result.cs
  sensitive = true
}