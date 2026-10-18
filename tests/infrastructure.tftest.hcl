mock_provider "docker" {}
mock_provider "cloudflare" {}

variables {
  cloudflare_dns_enabled = false
  cloudflare_main_domain = "local.io.vn"
  ssh_host               = "vm.example.com"
  ssh_user               = "deploy"
  acme_email             = "ops@example.com"
  ssh_host_key           = "ssh-ed25519 dGVzdA=="
  postgres_password      = "ephemeral-test-password"
  app_infisical_tokens = {
    service-a = "ephemeral-service-a-token"
    service-b = "ephemeral-service-b-token"
    invalid   = "ephemeral-invalid-token"
  }
}

run "runtime_routes" {
  command = plan
  variables {
    apps = {
      service-a = {
        image                = "example/service-a:1.0.0"
        domain               = "a.example.com"
        port                 = 3000
        user                 = "1000:1000"
        command              = ["node", "server.js"]
        infisical_project_id = "test-project"
        infisical_path       = "/service-a"
      }
      service-b = {
        image                = "example/service-b:1.0.0"
        domain               = "b.example.com"
        port                 = 8080
        user                 = "1000:1000"
        command              = ["/app/service-b"]
        infisical_project_id = "test-project"
        infisical_path       = "/service-b"
        database_access      = false
      }
    }
  }
  assert {
    condition     = docker_network.database.internal
    error_message = "Database network must not provide external routing."
  }
  assert {
    condition     = output.service_urls == { service-a = "https://a.example.com", service-b = "https://b.example.com" }
    error_message = "Each service must expose its own HTTPS URL."
  }
  assert {
    condition     = module.apps["service-a"].name == "iac-core-service-a" && output.database_container == "iac-core-postgres"
    error_message = "Resource names must follow the configured prefix."
  }
  assert {
    condition     = length(cloudflare_dns_record.traefik_main_domain) == 0 && length(cloudflare_dns_record.traefik_www) == 0 && length(cloudflare_dns_record.dockhand) == 0
    error_message = "Cloudflare DNS must remain disabled unless explicitly enabled."
  }
}

run "cloudflare_main_domain_a_record" {
  command = plan
  variables {
    cloudflare_dns_enabled = true
    cloudflare_main_domain = "seeu.pro.vn"
    cloudflare_zone_id     = "1234567890abcdef1234567890abcdef"
    ssh_host               = "203.0.113.10"
  }
  assert {
    condition = (
      cloudflare_dns_record.traefik_main_domain[0].type == "A" &&
      cloudflare_dns_record.traefik_main_domain[0].name == "seeu.pro.vn" &&
      cloudflare_dns_record.traefik_main_domain[0].content == "203.0.113.10" &&
      cloudflare_dns_record.traefik_main_domain[0].proxied
    )
    error_message = "The main domain must resolve through a proxied A record to the VM IPv4."
  }
  assert {
    condition = (
      length(cloudflare_dns_record.traefik_www) == 1 &&
      cloudflare_dns_record.traefik_www[0].zone_id == var.cloudflare_zone_id &&
      cloudflare_dns_record.traefik_www[0].name == "www.seeu.pro.vn" &&
      cloudflare_dns_record.traefik_www[0].type == "CNAME" &&
      cloudflare_dns_record.traefik_www[0].content == "seeu.pro.vn" &&
      cloudflare_dns_record.traefik_www[0].ttl == 1 &&
      cloudflare_dns_record.traefik_www[0].proxied
    )
    error_message = "www must be a proxied CNAME pointing to the main domain in the same zone."
  }
}

run "dockhand_public_dns" {
  command = plan
  variables {
    cloudflare_dns_enabled = true
    cloudflare_main_domain = "seeu.pro.vn"
    cloudflare_zone_id     = "1234567890abcdef1234567890abcdef"
    ssh_host               = "203.0.113.10"
  }
  assert {
    condition = (
      length(cloudflare_dns_record.dockhand) == 1 &&
      cloudflare_dns_record.dockhand[0].name == "dochand.seeu.pro.vn" &&
      cloudflare_dns_record.dockhand[0].type == "CNAME" &&
      cloudflare_dns_record.dockhand[0].content == "seeu.pro.vn" &&
      cloudflare_dns_record.dockhand[0].proxied &&
      cloudflare_dns_record.dockhand[0].ttl == 1 &&
      cloudflare_dns_record.dockhand[0].zone_id == var.cloudflare_zone_id
    )
    error_message = "Public Dockhand must have a proxied CNAME for the same hostname as its router."
  }
}

run "host_key_required_by_default" {
  command = plan
  variables {
    ssh_host_key = ""
  }
  expect_failures = [var.ssh_host_key]
}

run "diagnostic_mode_without_host_key" {
  command = plan
  variables {
    ssh_host_key_check = false
    ssh_host_key       = ""
  }
  assert {
    condition     = var.ssh_host_key_check == false
    error_message = "The explicit diagnostic bypass must be accepted without a pinned host key."
  }
}

run "invalid_app_port" {
  command = plan
  variables {
    apps = {
      invalid = {
        image                = "example/app:1"
        domain               = "invalid.example.com"
        port                 = 65536
        user                 = "1000:1000"
        command              = ["/app/run"]
        infisical_project_id = "test-project"
        infisical_path       = "/invalid"
      }
    }
  }
  expect_failures = [var.apps]
}

run "app_runtime_injection" {
  command = plan
  module {
    source = "./modules/app-container"
  }
  variables {
    name                  = "test-app"
    image                 = "example/app:1"
    memory_mb             = 256
    cpus                  = 0.5
    user                  = "1000:1000"
    networks              = ["proxy", "database"]
    environment           = { APP_ENV = "production" }
    labels                = { "traefik.enable" = "true" }
    command               = ["/app/run", "argument with spaces"]
    infisical_project_id  = "test-project"
    infisical_environment = "prod"
    infisical_path        = "/test-app"
    infisical_token_path  = "/opt/iac-core/secrets/apps/test-app-token"
  }
  assert {
    condition     = docker_container.this.cpus == "0.5" && docker_container.this.memory == 256
    error_message = "CPU and memory limits must reach the Docker provider unchanged."
  }
  assert {
    condition     = docker_container.this.env == toset(["APP_ENV=production"])
    error_message = "The Docker environment must not include an Infisical token."
  }
  assert {
    condition     = slice(docker_container.this.command, 5, 7) == tolist(["/app/run", "argument with spaces"])
    error_message = "Application arguments must retain their original boundaries."
  }
  assert {
    condition     = length(docker_container.this.ports) == 0 && length(docker_container.this.mounts) == 1
    error_message = "Apps must use routing networks and a single external token mount."
  }
}

run "database_storage" {
  command = plan
  module {
    source = "./modules/database"
  }
  variables {
    name               = "test-postgres"
    image              = "postgres:17-bookworm"
    network            = "database"
    password_file_path = "/opt/iac-core/secrets/postgres-password"
    memory_mb          = 1024
    cpus               = 1
  }
  assert {
    condition     = contains(docker_container.this.env, "POSTGRES_PASSWORD_FILE=/run/secrets/postgres-password")
    error_message = "PostgreSQL must read a host-provisioned password file."
  }
  assert {
    condition     = length(docker_container.this.ports) == 0 && docker_container.this.wait
    error_message = "PostgreSQL must not publish a host port and must wait for readiness."
  }
  assert {
    condition     = alltrue([for mount in docker_container.this.mounts : mount.read_only && mount.type == "bind"])
    error_message = "The PostgreSQL password mount must be read-only."
  }
}

run "traefik_tls" {
  command = plan
  module {
    source = "./modules/traefik"
  }

  variables {
    name           = "test-traefik"
    network        = "proxy"
    acme_email     = "ops@example.com"
    acme_ca_server = "https://acme-staging-v02.api.letsencrypt.org/directory"
    main_domain    = "local.io.vn"
  }
  assert {
    condition     = docker_image.this.name == "traefik:v3.6"
    error_message = "Traefik should use the image default declared in its module."
  }
  assert {
    condition = (
      contains(docker_container.this.command, "--providers.docker.exposedbydefault=false") &&
      contains(docker_container.this.command, "--api.dashboard=true") &&
      contains(docker_container.this.command, "--api.insecure=false") &&
      contains(docker_container.this.command, "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web")
    )
    error_message = "Traefik must use opt-in routing, a dashboard without the insecure API listener, and HTTP-01 certificates."
  }
  assert {
    condition     = toset([for port in docker_container.this.ports : port.external]) == toset([80, 443])
    error_message = "Only HTTP and HTTPS should be published."
  }
  assert {
    condition = alltrue([
      for key, value in {
        "traefik.http.routers.test-traefik-dashboard.rule"             = "Host(`proxy.local.io.vn`)"
        "traefik.http.routers.test-traefik-dashboard.entrypoints"      = "websecure"
        "traefik.http.routers.test-traefik-dashboard.tls"              = "true"
        "traefik.http.routers.test-traefik-dashboard.tls.certresolver" = "letsencrypt"
        "traefik.http.routers.test-traefik-dashboard.service"          = "api@internal"
      } : contains(docker_container.this.labels, { label = key, value = value })
    ])
    error_message = "The dashboard API and UI must share the HTTPS router."
  }
  assert {
    condition = (
      alltrue([
        for label in docker_container.this.labels :
        !endswith(label.label, ".middlewares") && !strcontains(label.label, ".basicauth.")
      ]) &&
      alltrue([
        for mount in docker_container.this.mounts :
        mount.target != "/run/secrets/dashboard-users"
      ])
    )
    error_message = "The dashboard must not attach authentication middleware or mount the former users file."
  }
}

run "dashboard_dns" {
  command = plan
  variables {
    cloudflare_dns_enabled = true
    cloudflare_main_domain = "seeu.pro.vn"
    cloudflare_zone_id     = "1234567890abcdef1234567890abcdef"
    ssh_host               = "203.0.113.10"
  }
  assert {
    condition = (
      cloudflare_dns_record.traefik_dashboard[0].name == "proxy.seeu.pro.vn" &&
      cloudflare_dns_record.traefik_dashboard[0].type == "CNAME" &&
      cloudflare_dns_record.traefik_dashboard[0].content == "seeu.pro.vn" &&
      cloudflare_dns_record.traefik_dashboard[0].proxied
    )
    error_message = "The proxy hostname must have a proxied CNAME pointing to the main domain."
  }
}

run "dockhand_is_networked_and_persistent" {
  command = plan
  module {
    source = "./modules/dockhand"
  }
  variables {
    name        = "test-dockhand"
    image       = "fnsys/dockhand:latest"
    network     = "proxy"
    main_domain = "local.io.vn"
    memory_mb   = 512
    cpus        = 0.5
  }
  assert {
    condition = (
      length(docker_container.this.ports) == 1 &&
      docker_container.this.ports[0].ip == "127.0.0.1" &&
      docker_container.this.ports[0].internal == 3000 &&
      docker_container.this.ports[0].external == 3000
    )
    error_message = "Dockhand must listen only on the host loopback interface."
  }
  assert {
    condition = (
      length(docker_container.this.mounts) == 1 &&
      anytrue([
        for mount in docker_container.this.mounts :
        mount.source == "/var/run/docker.sock" && mount.read_only
      ])
    )
    error_message = "Dockhand must receive read-only access to the Docker socket."
  }
  assert {
    condition = (
      length(docker_container.this.volumes) == 1 &&
      anytrue([
        for volume in docker_container.this.volumes :
        volume.container_path == "/app/data"
      ])
    )
    error_message = "Dockhand data must persist in a named Docker volume."
  }
  assert {
    condition = (
      length(docker_container.this.networks_advanced) == 1 &&
      alltrue([for network in docker_container.this.networks_advanced : network.name == "proxy"]) &&
      contains(docker_container.this.labels, { label = "traefik.enable", value = "true" })
    )
    error_message = "Dockhand must always join proxy with Traefik routing enabled."
  }
}

run "dockhand_https_router" {
  command = plan
  module {
    source = "./modules/dockhand"
  }
  variables {
    name        = "test-dockhand"
    main_domain = "local.io.vn"
    network     = "proxy"
  }
  assert {
    condition = alltrue([
      for key, value in {
        "traefik.enable"                                               = "true"
        "traefik.docker.network"                                       = "proxy"
        "traefik.http.routers.test-dockhand.rule"                      = "Host(`dochand.local.io.vn`)"
        "traefik.http.routers.test-dockhand.entrypoints"               = "websecure"
        "traefik.http.routers.test-dockhand.tls"                       = "true"
        "traefik.http.routers.test-dockhand.tls.certresolver"          = "letsencrypt"
        "traefik.http.routers.test-dockhand.service"                   = "test-dockhand"
        "traefik.http.services.test-dockhand.loadbalancer.server.port" = "3000"
      } : contains(docker_container.this.labels, { label = key, value = value })
    ])
    error_message = "Dockhand must use the requested hostname, HTTPS resolver and internal port 3000."
  }
  assert {
    condition = (
      length(docker_container.this.networks_advanced) == 1 &&
      anytrue([for network in docker_container.this.networks_advanced : network.name == "proxy"]) &&
      alltrue([for port in docker_container.this.ports : port.ip == "127.0.0.1"]) &&
      output.hostname == "dochand.local.io.vn"
    )
    error_message = "Dockhand must share the Traefik network without publishing an external application port."
  }
}

run "host_plan" {
  command = plan
  assert {
    condition     = output.docker_host == "ssh://deploy@vm.example.com:22"
    error_message = "The single root must expose the configured SSH endpoint."
  }
}

run "invalid_ssh_port" {
  command = plan
  variables {
    ssh_port = 0
  }
  expect_failures = [var.ssh_port]
}

run "missing_app_token" {
  command = plan
  variables {
    apps = {
      missing = {
        image                = "example/app:1"
        domain               = "missing.example.com"
        port                 = 3000
        user                 = "1000:1000"
        command              = ["/app/run"]
        infisical_project_id = "test-project"
        infisical_path       = "/missing"
      }
    }
    app_infisical_tokens = {}
  }
  expect_failures = [var.app_infisical_tokens]
}

run "empty_postgres_password" {
  command = plan
  variables {
    postgres_password = " "
  }
  expect_failures = [var.postgres_password]
}
