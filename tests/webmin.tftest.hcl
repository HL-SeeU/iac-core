mock_provider "docker" {}
mock_provider "cloudflare" {}

variables {
  cloudflare_dns_enabled = false
  cloudflare_main_domain = "seeu.pro.vn"
  ssh_host               = "203.0.113.10"
  ssh_user               = "deploy"
  ssh_host_key           = "ssh-ed25519 dGVzdA=="
  acme_email             = "ops@example.com"
  postgres_password      = "test-password"
  name                   = "test-traefik"
  network                = "proxy"
  main_domain            = "example.com"
  acme_ca_server         = "https://acme-staging-v02.api.letsencrypt.org/directory"
}

run "webmin_https_route" {
  command = plan

  assert {
    condition = (
      output.dynamic_service_urls == { "webmin.seeu.pro.vn" = "https://webmin.seeu.pro.vn" } &&
      length(cloudflare_dns_record.dynamic_service) == 0 &&
      local.traefik_dynamic_files["webmin.yml"] == file("${path.module}/config/traefik/dynamic/webmin.yml") &&
      yamldecode(local.traefik_dynamic_files["webmin.yml"]) == {
        http = {
          routers = {
            webmin = {
              rule        = "Host(`webmin.seeu.pro.vn`)"
              entryPoints = ["websecure"]
              service     = "webmin"
              tls         = { certResolver = "letsencrypt" }
            }
          }
          services = {
            webmin = {
              loadBalancer = {
                servers          = [{ url = "https://host.docker.internal:10000" }]
                serversTransport = "webmin-tls"
              }
            }
          }
          serversTransports = {
            webmin-tls = { insecureSkipVerify = true }
          }
        }
      }
    )
    error_message = "Webmin must load its static YAML from the shared dynamic directory with the HTTPS host backend and scoped self-signed transport."
  }
}

run "webmin_dns" {
  command = plan
  variables {
    cloudflare_dns_enabled = true
    cloudflare_zone_id     = "1234567890abcdef1234567890abcdef"
  }
  assert {
    condition = (
      length(cloudflare_dns_record.dynamic_service) == 1 &&
      cloudflare_dns_record.dynamic_service["webmin.seeu.pro.vn"].name == "webmin.seeu.pro.vn" &&
      cloudflare_dns_record.dynamic_service["webmin.seeu.pro.vn"].type == "CNAME" &&
      cloudflare_dns_record.dynamic_service["webmin.seeu.pro.vn"].content == "seeu.pro.vn" &&
      cloudflare_dns_record.dynamic_service["webmin.seeu.pro.vn"].zone_id == var.cloudflare_zone_id &&
      cloudflare_dns_record.dynamic_service["webmin.seeu.pro.vn"].proxied &&
      cloudflare_dns_record.dynamic_service["webmin.seeu.pro.vn"].ttl == 1
    )
    error_message = "Webmin DNS must match the hostname in the static route."
  }
}

run "host_rule_discovery" {
  command = plan
  assert {
    condition = toset(flatten([
      for rule in [
        "Host(`app.seeu.pro.vn`) || Host(`OTHER.seeu.pro.vn`)",
        "Host( `app.seeu.pro.vn` ) && PathPrefix(`/api`)",
        "HostRegexp(`.+\\.seeu\\.pro\\.vn`)",
        "HostSNI(`*`)",
        "PathPrefix(`/`)",
        ] : [
        for match in regexall(local.traefik_host_rule_pattern, rule) : lower(match[0])
      ]
    ])) == toset(["app.seeu.pro.vn", "other.seeu.pro.vn"])
    error_message = "Discover exact backtick Host matchers, normalize and deduplicate them, and ignore regex/TCP/path matchers."
  }
}

run "reject_host_outside_main_domain" {
  command = plan
  variables {
    cloudflare_dns_enabled = true
    cloudflare_main_domain = "example.com"
    cloudflare_zone_id     = "1234567890abcdef1234567890abcdef"
  }
  expect_failures = [cloudflare_dns_record.dynamic_service]
}

run "skip_separately_managed_dns" {
  command = plan
  variables {
    cloudflare_dns_enabled = true
    cloudflare_zone_id     = "1234567890abcdef1234567890abcdef"
  }
  override_module {
    target = module.dockhand
    outputs = {
      hostname = "webmin.seeu.pro.vn"
    }
  }
  assert {
    condition     = length(cloudflare_dns_record.dynamic_service) == 0
    error_message = "A hostname already owned by a separate DNS resource must not be created twice."
  }
}

run "docker_host_gateway" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  assert {
    condition = (
      contains(docker_container.this.host, {
        host = "host.docker.internal"
        ip   = "host-gateway"
      }) &&
      length(docker_container.this.networks_advanced) == 1 &&
      one(docker_container.this.networks_advanced).name == "proxy" &&
      length(docker_container.this.ports) == 2
    )
    error_message = "Host access must use a gateway alias without extra networks or a published Webmin port."
  }
}
