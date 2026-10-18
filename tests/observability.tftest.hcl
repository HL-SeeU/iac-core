mock_provider "docker" {}
mock_provider "cloudflare" {}

variables {
  cloudflare_dns_enabled = false
  cloudflare_main_domain = "example.com"
  ssh_host               = "vm.example.com"
  ssh_user               = "deploy"
  ssh_host_key           = "ssh-ed25519 dGVzdA=="
  acme_email             = "ops@example.com"
  postgres_password      = "test-password"
  name_prefix            = "iac-core"
  network                = "proxy"
  traefik_name           = "iac-core-traefik"
  host_root              = "/opt/iac-core"
  host_revision          = "test-host-revision"
  ssh = {
    host     = "vm.example.com"
    user     = "deploy"
    port     = 22
    host_key = "ssh-ed25519 dGVzdA=="
  }
}

run "disabled_without_cloud_configuration" {
  command = plan
  assert {
    condition     = !module.observability.enabled && module.observability.tracing_endpoint == ""
    error_message = "Existing deployments must not create a collector or require a Cloud token."
  }
}

run "cloud_observability" {
  command = plan
  variables {
    grafana_cloud = {
      metrics_url      = "https://prometheus.example.com/api/prom/push"
      metrics_username = "123"
      logs_url         = "https://logs.example.com/loki/api/v1/push"
      logs_username    = "456"
      otlp_url         = "https://otlp.example.com/otlp"
      otlp_username    = "789"
    }
    grafana_cloud_token = "ephemeral-test-cloud-token"
  }
  assert {
    condition     = module.observability.enabled && module.observability.tracing_endpoint == "http://iac-core-alloy:4318/v1/traces"
    error_message = "The root must wire Cloud inputs and expose the module's internal tracing endpoint."
  }
}

run "disabled_module" {
  command = plan
  module {
    source = "./modules/observability"
  }
  assert {
    condition = (
      length(docker_container.alloy) == 0 &&
      length(terraform_data.alloy_files) == 0 &&
      local.alloy_config == "" &&
      output.tracing_endpoint == ""
    )
    error_message = "The disabled module must create no collector or credential provisioner."
  }
}

run "alloy_runtime" {
  command = plan
  module {
    source = "./modules/observability"
  }
  variables {
    name_prefix  = "edge"
    traefik_name = "gateway"
    grafana_cloud = {
      metrics_url      = "https://prometheus.example.com/api/prom/push"
      metrics_username = "123"
      logs_url         = "https://logs.example.com/loki/api/v1/push"
      logs_username    = "456"
      otlp_url         = "https://otlp.example.com/otlp"
      otlp_username    = "789"
    }
    grafana_cloud_token = "ephemeral-test-cloud-token"
  }
  assert {
    condition = (
      docker_container.alloy[0].name == "edge-alloy" &&
      docker_volume.alloy[0].name == "edge-alloy-data" &&
      output.tracing_endpoint == "http://edge-alloy:4318/v1/traces" &&
      strcontains(local.alloy_config, "__address__ = \"gateway:8082\"")
    )
    error_message = "The reusable module must derive its own names and accept an independently named Traefik target."
  }
  assert {
    condition = (
      length(docker_container.alloy) == 1 &&
      length(docker_container.alloy[0].ports) == 0 &&
      length(docker_container.alloy[0].env) == 0 &&
      alltrue([for mount in docker_container.alloy[0].mounts : mount.read_only]) &&
      contains(docker_container.alloy[0].labels, { label = "traefik.enable", value = "false" })
    )
    error_message = "Alloy must use read-only mounts, no published ports, no environment secrets and no public route."
  }
  assert {
    condition = (
      strcontains(local.alloy_config, "sample_limit    = 7500") &&
      strcontains(local.alloy_config, "sample_limit    = 1500") &&
      strcontains(local.alloy_config, "scrape_interval = \"60s\"") &&
      strcontains(local.alloy_config, "rate  = 2") &&
      strcontains(local.alloy_config, "longer_than         = \"4KB\"") &&
      !strcontains(local.alloy_config, "ephemeral-test-cloud-token")
    )
    error_message = "Rendered configuration must retain the data-reduction budgets without embedding the token."
  }
}

run "cloud_requires_token" {
  command = plan
  module {
    source = "./modules/observability"
  }
  variables {
    grafana_cloud = {
      metrics_url      = "https://prometheus.example.com/api/prom/push"
      metrics_username = "123"
      logs_url         = "https://logs.example.com/loki/api/v1/push"
      logs_username    = "456"
      otlp_url         = "https://otlp.example.com/otlp"
      otlp_username    = "789"
    }
  }
  expect_failures = [var.grafana_cloud_token]
}

run "reject_insecure_or_wrong_cloud_endpoints" {
  command = plan
  module {
    source = "./modules/observability"
  }
  variables {
    grafana_cloud = {
      metrics_url      = "http://prometheus.example.com/api/prom/push"
      metrics_username = "123"
      logs_url         = "https://logs.example.com"
      logs_username    = "456"
      otlp_url         = "https://otlp.example.com/otlp/v1/traces"
      otlp_username    = "789"
    }
    grafana_cloud_token = "test"
  }
  expect_failures = [var.grafana_cloud]
}

run "traefik_observability" {
  command = plan
  module {
    source = "./modules/traefik"
  }
  variables {
    name                  = "test-traefik"
    network               = "proxy"
    main_domain           = "example.com"
    acme_ca_server        = "https://acme-staging-v02.api.letsencrypt.org/directory"
    observability_enabled = true
    tracing_endpoint      = "http://test-alloy:4318/v1/traces"
  }
  assert {
    condition = alltrue([
      for flag in [
        "--entrypoints.metrics.address=:8082",
        "--metrics.prometheus.addrouterslabels=false",
        "--accesslog.format=json",
        "--accesslog.fields.defaultmode=drop",
        "--accesslog.fields.headers.defaultmode=drop",
        "--tracing.samplerate=0.1",
        "--tracing.otlp.http.endpoint=http://test-alloy:4318/v1/traces",
      ] : contains(docker_container.this.command, flag)
    ])
    error_message = "Traefik must expose internal metrics, privacy-filtered JSON access logs and 10% traces."
  }
  assert {
    condition     = toset([for port in docker_container.this.ports : port.external]) == toset([80, 443])
    error_message = "Observability must not publish metrics or OTLP ports on the host."
  }
}
