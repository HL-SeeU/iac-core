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
