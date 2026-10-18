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

resource "cloudflare_dns_record" "traefik_www" {
  count = var.cloudflare_dns_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = "www.${var.cloudflare_main_domain}"
  type    = "A"
  content = var.ssh_host
  ttl     = 1
  proxied = true
  comment = "Terraform-managed www alias for Traefik"
}

resource "cloudflare_dns_record" "dockhand" {
  count = var.cloudflare_dns_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = module.dockhand.hostname
  type    = "CNAME"
  content = cloudflare_dns_record.traefik_main_domain[0].name
  ttl     = 1
  proxied = true
  comment = "Terraform-managed Dockhand HTTPS hostname"
}

resource "cloudflare_dns_record" "traefik_dashboard" {
  count = var.cloudflare_dns_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = module.traefik.dashboard_hostname
  type    = "CNAME"
  content = cloudflare_dns_record.traefik_main_domain[0].name
  ttl     = 1
  proxied = true
  comment = "Terraform-managed Traefik dashboard"
}

resource "cloudflare_dns_record" "dynamic_service" {
  for_each = var.cloudflare_dns_enabled ? setsubtract(local.traefik_dynamic_hostnames, toset([
    lower(var.cloudflare_main_domain),
    lower("www.${var.cloudflare_main_domain}"),
    lower(module.dockhand.hostname),
    lower(module.traefik.dashboard_hostname),
  ])) : toset([])

  zone_id = var.cloudflare_zone_id
  name    = each.key
  type    = "CNAME"
  content = cloudflare_dns_record.traefik_main_domain[0].name
  ttl     = 1
  proxied = true
  comment = "Terraform-managed Traefik dynamic service"

  lifecycle {
    precondition {
      condition = (
        length(each.key) <= 253 &&
        can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", each.key)) &&
        endswith(each.key, ".${lower(var.cloudflare_main_domain)}")
      )
      error_message = "Dynamic HTTP Host domains must be valid subdomains of cloudflare_main_domain: ${each.key}."
    }
  }
}
