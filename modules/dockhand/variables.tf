variable "name" {
  type = string
}

variable "image" {
  type        = string
  default     = "fnsys/dockhand:latest"
  description = "Dockhand image; pin to a reviewed version or digest for repeatable deployments."
}

variable "memory_mb" {
  type        = number
  default     = 512
  description = "Dockhand memory limit in MB."
  validation {
    condition     = var.memory_mb >= 128 && floor(var.memory_mb) == var.memory_mb
    error_message = "Dockhand memory must be an integer of at least 128 MB."
  }
}

variable "cpus" {
  type        = number
  default     = 0.5
  description = "Dockhand CPU quota."
  validation {
    condition     = var.cpus > 0
    error_message = "Dockhand CPU quota must be positive."
  }
}

variable "sub_domain" {
  type        = string
  default     = "dochand"
  description = "Subdomain for the Dockhand service."
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.sub_domain))
    error_message = "Dockhand sub_domain must be a valid lowercase DNS label."
  }
}

variable "main_domain" {
  type        = string
  description = "Parent domain for the Dockhand HTTPS hostname."
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*\\.[A-Za-z]{2,}$", var.main_domain))
    error_message = "A valid main_domain is required for the public Dockhand route."
  }
}

variable "network" {
  type        = string
  description = "Docker proxy network always shared with Traefik."
  validation {
    condition     = length(trimspace(var.network)) > 0
    error_message = "A non-empty Traefik network is required for Dockhand."
  }
}
