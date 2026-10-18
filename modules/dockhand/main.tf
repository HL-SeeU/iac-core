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
  user    = "0:0"
  memory  = var.memory_mb
  cpus    = tostring(var.cpus)

  networks_advanced {
    name = var.network
  }

  dynamic "labels" {
    for_each = {
      "traefik.enable"                                               = "true"
      "traefik.docker.network"                                       = var.network
      "traefik.http.routers.${var.name}.rule"                        = "Host(`${var.sub_domain}.${var.main_domain}`)"
      "traefik.http.routers.${var.name}.entrypoints"                 = "websecure"
      "traefik.http.routers.${var.name}.tls"                         = "true"
      "traefik.http.routers.${var.name}.tls.certresolver"            = "letsencrypt"
      "traefik.http.routers.${var.name}.service"                     = var.name
      "traefik.http.services.${var.name}.loadbalancer.server.port"   = "3000"
      "traefik.http.services.${var.name}.loadbalancer.server.scheme" = "http"
    }
    content {
      label = labels.key
      value = labels.value
    }
  }

  ports {
    internal = 3000
    external = 3000
    ip       = "127.0.0.1"
  }

  mounts {
    type      = "bind"
    source    = "/var/run/docker.sock"
    target    = "/var/run/docker.sock"
    read_only = true
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/app/data"
  }

  log_driver = "json-file"
  log_opts   = { "max-size" = "10m", "max-file" = "3" }
}
