variable "name" {
  type = string
}

variable "image" {
  type        = string
  default     = "traefik:v3.6"
  description = "Traefik image; pin to a reviewed digest for production."
}

variable "network" {
  type = string
}

variable "tcp_entrypoints" {
  type        = map(number)
  default     = {}
  nullable    = false
  description = "Additional TCP entrypoint names and ports, published on all IPv4 host interfaces."
  validation {
    condition = alltrue([
      for name, port in var.tcp_entrypoints :
      port == null ? false : (
        can(regex("^[a-z][a-z0-9-]*$", name)) &&
        !contains(["web", "websecure", "traefik", "metrics"], name) &&
        port >= 1 && port <= 65535 && floor(port) == port &&
        !contains([80, 443, 8080, 8082], port)
      )
    ])
    error_message = "TCP entrypoints need lowercase names and integer ports 1-65535; built-in names and ports (80, 443, 8080, 8082) are reserved."
  }
  validation {
    condition     = length(distinct(values(var.tcp_entrypoints))) == length(var.tcp_entrypoints)
    error_message = "Each TCP entrypoint must use a distinct port."
  }
}

variable "dynamic_config_directory" {
  type        = string
  default     = null
  description = "Optional existing Linux host directory mounted read-only for the watched file provider."
  validation {
    condition = var.dynamic_config_directory == null ? true : can(regex(
      "^/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$", var.dynamic_config_directory
    ))
    error_message = "dynamic_config_directory must be an absolute Linux path containing only letters, digits, underscores and hyphens."
  }
}

variable "observability_enabled" {
  type    = bool
  default = false
}

variable "tracing_endpoint" {
  type    = string
  default = ""
  validation {
    condition     = !var.observability_enabled || can(regex("^http://[a-z0-9-]+:4318/v1/traces$", var.tracing_endpoint))
    error_message = "Observability requires an internal Alloy OTLP HTTP endpoint on port 4318."
  }
}

variable "acme_email" {
  type = string
}

variable "acme_ca_server" {
  type = string
}

variable "main_domain" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*\\.[A-Za-z]{2,}$", var.main_domain))
    error_message = "A valid main_domain is required for the proxy dashboard hostname."
  }
}
