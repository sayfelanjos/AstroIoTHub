variable "location" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type    = string
  default = "AstroIoTHub-RG"
}

variable "iothub_name" {
  type    = string
  default = "AstroIoTHub"
}

variable "iothub_sku" {
  type    = string
  default = "S1"
}

variable "iothub_units" {
  type    = number
  default = 1
}

variable "storage_account_name" {
  type    = string
  default = "astrostorage"
}

variable "storage_container_name" {
  type    = string
  default = "telemetria-bruta"
}

variable "stream_job_name" {
  type    = string
  default = "AstroStream"
}
