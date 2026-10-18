variable "cloudflare_dns_enabled" {
  type        = bool
  default     = true
  description = "Enable Terraform management of the main-domain Cloudflare A record."
}

variable "cloudflare_main_domain" {
  type        = string
  default     = ""
  description = "Main domain whose A record points to the Traefik VM."
  validation {
    condition = (
      !var.cloudflare_dns_enabled ||
      can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*\\.[A-Za-z]{2,}$", var.cloudflare_main_domain))
    )
    error_message = "Set cloudflare_main_domain to a valid fully-qualified domain when Cloudflare DNS is enabled."
  }
}

variable "cloudflare_zone_id" {
  type        = string
  default     = ""
  description = "Cloudflare zone ID containing cloudflare_main_domain."
  validation {
    condition = (
      !var.cloudflare_dns_enabled ||
      can(regex("^[A-Fa-f0-9]{32}$", var.cloudflare_zone_id))
    )
    error_message = "Set cloudflare_zone_id to the 32-character Cloudflare zone ID when Cloudflare DNS is enabled."
  }
}
