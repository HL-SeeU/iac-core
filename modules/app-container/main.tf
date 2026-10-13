resource "docker_image" "this" {
  name         = var.image
  keep_locally = true
}

resource "terraform_data" "secret_revision" {
  triggers_replace = var.secret_revision
}

resource "docker_container" "this" {
  name    = var.name
  image   = docker_image.this.image_id
  restart = "unless-stopped"
  memory  = var.memory_mb
  cpus    = tostring(var.cpus)
  user    = var.user

  env        = [for key, value in var.environment : "${key}=${value}"]
  entrypoint = ["/bin/sh", "-ec"]
  command = concat([
    <<-EOT
      INFISICAL_TOKEN="$(cat /run/secrets/infisical-token)"
      test -n "$INFISICAL_TOKEN" || { echo "Infisical token file is empty" >&2; exit 1; }
      export INFISICAL_TOKEN
      project_id="$1"; environment="$2"; secret_path="$3"
      shift 3
      exec infisical run --projectId="$project_id" --env="$environment" --path="$secret_path" -- "$@"
    EOT
    ,
    "infisical-entrypoint",
    var.infisical_project_id,
    var.infisical_environment,
    var.infisical_path,
  ], var.command)

  mounts {
    type      = "bind"
    source    = var.infisical_token_path
    target    = "/run/secrets/infisical-token"
    read_only = true
  }

  dynamic "networks_advanced" {
    for_each = toset(var.networks)
    content {
      name = networks_advanced.value
    }
  }

  dynamic "labels" {
    for_each = var.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  dynamic "healthcheck" {
    for_each = var.healthcheck == null ? [] : [var.healthcheck]
    content {
      test         = healthcheck.value
      interval     = "30s"
      timeout      = "5s"
      retries      = 3
      start_period = "30s"
    }
  }

  wait         = var.healthcheck != null
  wait_timeout = 180
  log_driver   = "json-file"
  log_opts     = { "max-size" = "10m", "max-file" = "3" }

  lifecycle {
    replace_triggered_by = [terraform_data.secret_revision]
  }
}
