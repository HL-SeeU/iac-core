mock_provider "docker" {}

variables {
  ssh_host          = "vm.example.com"
  ssh_user          = "deploy"
  acme_email        = "ops@example.com"
  ssh_host_key      = "ssh-ed25519 dGVzdA=="
  postgres_password = "ephemeral-test-password"
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
    image          = "traefik:v3.6"
    network        = "proxy"
    acme_email     = "ops@example.com"
    acme_ca_server = "https://acme-staging-v02.api.letsencrypt.org/directory"
  }
  assert {
    condition = (
      contains(docker_container.this.command, "--providers.docker.exposedbydefault=false") &&
      contains(docker_container.this.command, "--api.dashboard=false") &&
      contains(docker_container.this.command, "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web")
    )
    error_message = "Traefik must use opt-in routing, no dashboard, and HTTP-01 certificates."
  }
  assert {
    condition     = toset([for port in docker_container.this.ports : port.external]) == toset([80, 443])
    error_message = "Only HTTP and HTTPS should be published."
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
