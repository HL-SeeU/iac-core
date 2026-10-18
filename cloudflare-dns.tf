resource "cloudflare_dns_record" "traefik_main_domain" {
  count = var.cloudflare_dns_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.cloudflare_main_domain
  type    = "A"
  content = var.ssh_host
  ttl     = 1
  proxied = true
  comment = "Terraform-managed Traefik origin"

  lifecycle {
    precondition {
      condition     = can(cidrnetmask("${var.ssh_host}/32"))
      error_message = "TF_VAR_ssh_host must be the VM's public IPv4 address when managing a Cloudflare A record."
    }
  }

  depends_on = [module.traefik]
}
