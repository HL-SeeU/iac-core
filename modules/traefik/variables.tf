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

variable "acme_email" {
  type = string
}

variable "acme_ca_server" {
  type = string
}
