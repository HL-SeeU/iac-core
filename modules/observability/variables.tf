variable "name_prefix" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "Use lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "network" {
  type = string
}

variable "traefik_name" {
  type = string
}

variable "host_root" {
  type = string
  validation {
    condition     = can(regex("^/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$", var.host_root))
    error_message = "Use an absolute path containing only letters, digits, underscores and hyphens."
  }
}

variable "host_revision" {
  type        = string
  description = "Host preparation resource ID; a change redelivers configuration and credentials."
}

variable "credentials_revision" {
  type        = string
  default     = "1"
  description = "Bump after rotating the Cloud token."
}

variable "ssh" {
  type = object({
    host     = string
    user     = string
    port     = number
    host_key = string
  })
  description = "Provisioning SSH connection. An empty host_key explicitly disables host-key verification."
}

variable "grafana_cloud" {
  description = "Enable Alloy with non-secret connection details from Grafana Cloud. null leaves observability disabled."
  type = object({
    metrics_url      = string
    metrics_username = string
    logs_url         = string
    logs_username    = string
    otlp_url         = string
    otlp_username    = string
  })
  default = null
  validation {
    condition = var.grafana_cloud == null ? true : (
      alltrue([
        for url in [var.grafana_cloud.metrics_url, var.grafana_cloud.logs_url, var.grafana_cloud.otlp_url] :
        can(regex("^https://[A-Za-z0-9.-]+(:443)?/[^?#[:space:]]*$", url))
      ]) &&
      endswith(var.grafana_cloud.metrics_url, "/api/prom/push") &&
      endswith(var.grafana_cloud.logs_url, "/loki/api/v1/push") &&
      endswith(var.grafana_cloud.otlp_url, "/otlp") &&
      alltrue([
        for username in [var.grafana_cloud.metrics_username, var.grafana_cloud.logs_username, var.grafana_cloud.otlp_username] :
        can(regex("^[0-9]+$", username))
      ])
    )
    error_message = "Use the HTTPS Prometheus remote-write URL, Loki push URL, OTLP base URL ending /otlp, and numeric tenant IDs copied from Grafana Cloud."
  }
}

variable "grafana_cloud_token" {
  type        = string
  default     = ""
  sensitive   = true
  ephemeral   = true
  description = "Cloud access-policy token with metrics:write, logs:write and traces:write. Delivered only through an SSH provisioner."
  validation {
    condition     = var.grafana_cloud == null || length(trimspace(var.grafana_cloud_token)) > 0
    error_message = "Provide a non-empty grafana_cloud_token when grafana_cloud is configured."
  }
}
