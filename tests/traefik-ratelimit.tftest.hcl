mock_provider "docker" {}

variables {
  name           = "test-traefik"
  network        = "proxy"
  main_domain    = "example.com"
  acme_email     = "ops@example.com"
  acme_ca_server = "https://acme-staging-v02.api.letsencrypt.org/directory"
}

run "direct_client_rate_limit" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  assert {
    condition = (
      contains(docker_container.this.command, "--entrypoints.websecure.http.middlewares=test-traefik-global-limit@docker") &&
      contains(docker_container.this.command, "--entrypoints.web.http.redirections.entrypoint.to=websecure") &&
      length(docker_container.this.ports) == 2
    )
    error_message = "The default HTTPS rate limit must preserve the HTTP redirect and published ports."
  }
  assert {
    condition = alltrue([
      for key, value in {
        "traefik.http.middlewares.test-traefik-global-limit.ratelimit.average" = "100"
        "traefik.http.middlewares.test-traefik-global-limit.ratelimit.period"  = "1s"
        "traefik.http.middlewares.test-traefik-global-limit.ratelimit.burst"   = "200"
      } : contains(docker_container.this.labels, { label = key, value = value })
    ])
    error_message = "The rate limit must be 100 requests per second with burst capacity 200."
  }
  assert {
    condition = (
      length([for arg in docker_container.this.command : arg if strcontains(arg, "forwardedheaders")]) == 0 &&
      length([for label in docker_container.this.labels : label if strcontains(label.label, "sourcecriterion")]) == 0
    )
    error_message = "Without trusted proxies the limiter must use the connection IP, not client-supplied forwarded headers."
  }
}

run "trusted_proxy_rate_limit" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  variables {
    trusted_proxy_cidrs = ["173.245.48.0/20", "2400:cb00::/32"]
    tcp_entrypoints     = { mysql = 3306 }
  }
  assert {
    condition = (
      contains(docker_container.this.command, "--entrypoints.websecure.forwardedheaders.trustedips=173.245.48.0/20,2400:cb00::/32") &&
      contains(docker_container.this.labels, {
        label = "traefik.http.middlewares.test-traefik-global-limit.ratelimit.sourcecriterion.ipstrategy.depth"
        value = "1"
      }) &&
      !contains(docker_container.this.command, "--entrypoints.websecure.forwardedheaders.insecure=true")
    )
    error_message = "The one-hop limiter must select the forwarded client IP and only trust configured IPv4/IPv6 proxies."
  }
  assert {
    condition = (
      contains(docker_container.this.command, "--entrypoints.mysql.address=:3306") &&
      length(docker_container.this.ports) == 3 &&
      length([for arg in docker_container.this.command : arg if startswith(arg, "--entrypoints.mysql.http.")]) == 0
    )
    error_message = "HTTPS rate limiting must not alter raw TCP listeners."
  }
}

run "reject_invalid_trusted_proxy" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  variables {
    trusted_proxy_cidrs = ["not-a-cidr"]
  }
  expect_failures = [var.trusted_proxy_cidrs]
}
