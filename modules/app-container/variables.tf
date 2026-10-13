variable "name" {
  type = string
}

variable "image" {
  type = string
}

variable "user" {
  type        = string
  description = "Container UID:GID or username with read access to its token file."
}

variable "memory_mb" {
  type = number
}

variable "cpus" {
  type = number
}

variable "command" {
  type        = list(string)
  description = "Explicit application command executed by Infisical."
}

variable "environment" {
  type        = map(string)
  default     = {}
  description = "Non-secret configuration only; values are stored in Terraform state."
}

variable "networks" {
  type = list(string)
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "infisical_project_id" {
  type = string
}

variable "infisical_environment" {
  type = string
}

variable "infisical_path" {
  type = string
}

variable "infisical_token_path" {
  type        = string
  description = "Existing service-scoped token file on the Docker host."
}

variable "healthcheck" {
  type        = list(string)
  default     = null
  description = "Optional Docker healthcheck test, e.g. [CMD, executable, argument]."
}

variable "secret_revision" {
  type        = string
  default     = "1"
  description = "Non-secret revision that recreates the container after token delivery."
}
