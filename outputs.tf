# Output do IP para acesso fácil
output "public_ip_address" {
  value = azurerm_public_ip.pip.ip_address
}