resource "docker_image" "this" {
  name         = var.image
  keep_locally = true
}

resource "docker_volume" "data" {
  name = "${var.name}-data"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "this" {
  name    = var.name
  image   = docker_image.this.image_id
  restart = "unless-stopped"
  memory  = var.memory_mb
  cpus    = tostring(var.cpus)

  env = [
    "POSTGRES_USER=postgres",
    "POSTGRES_DB=postgres",
    "POSTGRES_PASSWORD_FILE=/run/secrets/postgres-password",
    "POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256",
  ]

  mounts {
    type      = "bind"
    source    = var.password_file_path
    target    = "/run/secrets/postgres-password"
    read_only = true
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name    = var.network
    aliases = ["postgres"]
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U postgres -d postgres"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 12
    start_period = "30s"
  }

  labels {
    label = "traefik.enable"
    value = "false"
  }

  wait         = true
  wait_timeout = 180
  log_driver   = "json-file"
  log_opts     = { "max-size" = "10m", "max-file" = "3" }
}
