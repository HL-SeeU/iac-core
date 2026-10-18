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
