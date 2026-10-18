variable "grafana_cloud" {
  description = "Infisical-loaded Cloud connection details passed to the observability module. null disables collection."
  type = object({
    metrics_url      = string
    metrics_username = string
    logs_url         = string
    logs_username    = string
    otlp_url         = string
    otlp_username    = string
  })
  default = null
}

variable "grafana_cloud_token" {
  type        = string
  default     = ""
  sensitive   = true
  ephemeral   = true
  description = "Infisical-loaded Cloud token, passed ephemerally to the observability module."
}
