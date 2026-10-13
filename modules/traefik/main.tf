resource "docker_image" "this" {
  name         = var.image
  keep_locally = true
}

resource "docker_volume" "acme" {
  name = "${var.name}-acme"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "this" {
  name    = var.name
  image   = docker_image.this.image_id
  restart = "unless-stopped"
  memory  = 256
  cpus    = "0.5"

  command = [
    "--api.dashboard=false",
    "--providers.docker=true",
    "--providers.docker.exposedbydefault=false",
    "--providers.docker.network=${var.network}",
    "--entrypoints.web.address=:80",
    "--entrypoints.websecure.address=:443",
    "--entrypoints.web.http.redirections.entrypoint.to=websecure",
    "--entrypoints.web.http.redirections.entrypoint.scheme=https",
    "--certificatesresolvers.letsencrypt.acme.email=${var.acme_email}",
    "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json",
    "--certificatesresolvers.letsencrypt.acme.caserver=${var.acme_ca_server}",
    "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web",
    "--ping=true",
  ]

  ports {
    internal = 80
    external = 80
  }

  ports {
    internal = 443
    external = 443
  }

  mounts {
    type      = "bind"
    source    = "/var/run/docker.sock"
    target    = "/var/run/docker.sock"
    read_only = true
  }

  volumes {
    volume_name    = docker_volume.acme.name
    container_path = "/letsencrypt"
  }

  networks_advanced {
    name = var.network
  }

  healthcheck {
    test     = ["CMD", "traefik", "healthcheck", "--ping"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }

  wait         = true
  wait_timeout = 120
  log_driver   = "json-file"
  log_opts     = { "max-size" = "10m", "max-file" = "3" }
}
