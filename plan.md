## Plano: Projeto Azure com Terraform para AstroIoTHub

TL;DR - Criar um MVP Terraform para provisionar IoT Hub, Storage Account e Stream Analytics na Azure, documentar variáveis e gerar outputs úteis para integração com Python.

### Passos

1. Definir a infraestrutura necessária e os nomes de recursos no Terraform.
   - Azure IoT Hub na camada S1.
   - Azure Storage Account com container Blob para telemetria-bruta.
   - Azure Stream Analytics job com input do IoT Hub e output para Blob Storage.

2. Criar o arquivo principal de Terraform (`main.tf`).
   - Configurar provider `azurerm`.
   - Declarar `azurerm_resource_group`.
   - Declarar `azurerm_iothub` com plano S1.
   - Declarar `azurerm_storage_account` e `azurerm_storage_container`.
   - Declarar `azurerm_stream_analytics_job`, `azurerm_stream_analytics_input_eventhub` ou equivalente para IoT Hub e `azurerm_stream_analytics_output_blob`.

3. Criar variáveis e outputs.
   - `variables.tf` com nome e região padrão.
   - `outputs.tf` para exposição de strings de conexão e outros valores úteis.

4. Documentar a etapa manual de criação do dispositivo no IoT Hub e como obter a Primary Connection String.
   - Incluir instruções para criar `RaspberryPiAstro` no menu Devices do IoT Hub.
   - Explicar que a conexão primária será usada no código Python.

5. Validar e testar.
   - Executar `terraform init`, `terraform plan` e `terraform apply`.
   - Confirmar o provisionamento no portal Azure.
   - Confirmar que o container `telemetria-bruta` foi criado e que o Stream Analytics job está configurado.

### Verificação

- Confirmar que o recurso `azurerm_iothub` foi criado com SKU `S1`.
- Confirmar que o `azurerm_storage_account` contém o container `telemetria-bruta`.
- Confirmar que o Stream Analytics job está conectado ao IoT Hub e escreve em Blob Storage.
- Verificar se há um output Terraform com a connection string do IoT Hub ou instruções para obtê-la.

### Decisões

- MVP foca em provisionar os três recursos Azure e garantir fluidez de ponta a ponta.
- Otimização de custo fica para depois da validação inicial.
- O dispositivo `RaspberryPiAstro` é criado manualmente no IoT Hub, pois o fluxo de obtenção da connection string é específico e normalmente não é gerado automaticamente pelo Terraform.

### Further Considerations

1. Se precisar, podemos incluir um script auxiliar Terraform ou Azure CLI para criar o dispositivo IoT Hub e recuperar a Primary Connection String automaticamente.
2. A query do Stream Analytics será simples: `SELECT * INTO [BlobOutput] FROM [IoTHubInput]`.
