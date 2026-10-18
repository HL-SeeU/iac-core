mock_provider "docker" {}
mock_provider "cloudflare" {}

variables {
  cloudflare_dns_enabled = false
  cloudflare_main_domain = "example.com"
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

run "public_mysql_endpoint" {
  command = plan
  assert {
    condition     = output.mysql_endpoint == "203.0.113.10:3306"
    error_message = "The public MySQL endpoint must use ssh_host and port 3306."
  }
  assert {
    condition = (
      local.traefik_tcp_entrypoints == { mysql = 3306 } &&
      local.traefik_dynamic_directory == "/opt/iac-core/traefik/dynamic" &&
      terraform_data.traefik_files.triggers_replace[2] == sha256(jsonencode(local.traefik_dynamic_files)) &&
      yamldecode(local.traefik_dynamic_files["mysql.yml"]) == {
        tcp = {
          routers = {
            mysql = {
              entryPoints = ["mysql"]
              rule        = "HostSNI(`*`)"
              service     = "mysql"
            }
          }
          services = {
            mysql = {
              loadBalancer = {
                servers = [{ address = "10.0.0.91:3306" }]
              }
            }
          }
        }
      }
    )
    error_message = "The root must own the MySQL listener and raw TCP route, with file-content changes triggering synchronization."
  }
}

run "multiple_tcp_services" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  variables {
    tcp_entrypoints = {
      mysql = 3306
      redis = 6379
    }
    dynamic_config_directory = "/opt/iac-core/traefik/dynamic"
  }
  assert {
    condition = (
      contains(docker_container.this.command, "--entrypoints.mysql.address=:3306") &&
      contains(docker_container.this.command, "--entrypoints.redis.address=:6379") &&
      contains(docker_container.this.command, "--providers.file.directory=/etc/traefik/dynamic") &&
      contains(docker_container.this.command, "--providers.file.watch=true") &&
      contains(docker_container.this.command, "--entrypoints.web.address=:80") &&
      contains(docker_container.this.command, "--entrypoints.websecure.address=:443") &&
      length(docker_container.this.ports) == 4 &&
      length([for port in docker_container.this.ports : port if
        port.internal == 3306 && port.external == 3306 &&
        port.ip == "0.0.0.0" && port.protocol == "tcp"
      ]) == 1 &&
      length([for port in docker_container.this.ports : port if
        port.internal == 6379 && port.external == 6379 &&
        port.ip == "0.0.0.0" && port.protocol == "tcp"
      ]) == 1
    )
    error_message = "Additional TCP listeners must publish their ports without replacing HTTP/HTTPS."
  }
  assert {
    condition = (
      length(docker_container.this.upload) == 0 &&
      length([for mount in docker_container.this.mounts : mount if
        mount.type == "bind" &&
        mount.source == "/opt/iac-core/traefik/dynamic" &&
        mount.target == "/etc/traefik/dynamic" &&
        mount.read_only
      ]) == 1
    )
    error_message = "Traefik must watch a read-only directory mount instead of embedding service-specific configuration."
  }
}

run "mysql_disabled_by_default" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  assert {
    condition = (
      length(docker_container.this.ports) == 2 &&
      length(docker_container.this.upload) == 0 &&
      !contains(docker_container.this.command, "--entrypoints.mysql.address=:3306") &&
      !contains(docker_container.this.command, "--providers.file.directory=/etc/traefik/dynamic") &&
      length(docker_container.this.mounts) == 1
    )
    error_message = "Module callers that do not configure MySQL must retain their existing listeners."
  }
}

run "reject_reserved_entrypoint" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  variables {
    tcp_entrypoints = { web = 3306 }
  }
  expect_failures = [var.tcp_entrypoints]
}

run "reject_reserved_port" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  variables {
    tcp_entrypoints = { database = 443 }
  }
  expect_failures = [var.tcp_entrypoints]
}

run "reject_duplicate_ports" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  variables {
    tcp_entrypoints = { mysql = 3306, other = 3306 }
  }
  expect_failures = [var.tcp_entrypoints]
}

run "reject_invalid_ports" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  variables {
    tcp_entrypoints = { zero = 0, oversized = 65536, fractional = 3306.5, missing = null }
  }
  expect_failures = [var.tcp_entrypoints]
}

run "reject_invalid_entrypoint_name" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  variables {
    tcp_entrypoints = { "bad.name" = 3306 }
  }
  expect_failures = [var.tcp_entrypoints]
}

run "reject_relative_config_directory" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  variables {
    dynamic_config_directory = "relative/dynamic"
  }
  expect_failures = [var.dynamic_config_directory]
}
