variable "name" {
  type = string
}

variable "image" {
  type = string
}

variable "network" {
  type = string
}

variable "password_file_path" {
  type        = string
  description = "Existing secret file on the Docker host, never read by Terraform."
}

variable "memory_mb" {
  type = number
}

variable "cpus" {
  type = number
}
