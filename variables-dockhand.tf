variable "dockhand_image" {
  type        = string
  default     = "fnsys/dockhand:latest"
  description = "Dockhand image; pin to a reviewed version or digest for repeatable deployments."
}

variable "dockhand_memory_mb" {
  type        = number
  default     = 512
  description = "Dockhand memory limit in MB."
  validation {
    condition     = var.dockhand_memory_mb >= 128 && floor(var.dockhand_memory_mb) == var.dockhand_memory_mb
    error_message = "Dockhand memory must be an integer of at least 128 MB."
  }
}

variable "dockhand_cpus" {
  type        = number
  default     = 0.5
  description = "Dockhand CPU quota."
  validation {
    condition     = var.dockhand_cpus > 0
    error_message = "Dockhand CPU quota must be positive."
  }
}
