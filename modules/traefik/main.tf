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
  memory  = 1024
  cpus    = "2.0"

  command = concat([
    "--api.dashboard=true",
    "--api.insecure=false",
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
    ], var.observability_enabled ? [
    "--accesslog=true",
    "--accesslog.format=json",
    "--accesslog.fields.defaultmode=drop",
    "--accesslog.fields.headers.defaultmode=drop",
    "--accesslog.fields.names.StartUTC=keep",
    "--accesslog.fields.names.DownstreamStatus=keep",
    "--accesslog.fields.names.Duration=keep",
    "--accesslog.fields.names.RequestMethod=keep",
    "--accesslog.fields.names.RouterName=keep",
    "--accesslog.fields.names.ServiceName=keep",
    "--accesslog.fields.names.TraceId=keep",
    "--accesslog.fields.names.SpanId=keep",
    "--entrypoints.metrics.address=:8082",
    "--metrics.prometheus=true",
    "--metrics.prometheus.entrypoint=metrics",
    "--metrics.prometheus.addrouterslabels=false",
    "--metrics.prometheus.addentrypointslabels=true",
    "--metrics.prometheus.addserviceslabels=true",
    "--tracing=true",
    "--tracing.servicename=${var.name}",
    "--tracing.samplerate=0.1",
    "--tracing.otlp.http=true",
    "--tracing.otlp.http.endpoint=${var.tracing_endpoint}",
  ] : [])

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

  dynamic "labels" {
    for_each = {
      "traefik.enable"                                              = "true"
      "traefik.docker.network"                                      = var.network
      "traefik.http.routers.${var.name}-dashboard.rule"             = "Host(`proxy.${var.main_domain}`)"
      "traefik.http.routers.${var.name}-dashboard.entrypoints"      = "websecure"
      "traefik.http.routers.${var.name}-dashboard.tls"              = "true"
      "traefik.http.routers.${var.name}-dashboard.tls.certresolver" = "letsencrypt"
      "traefik.http.routers.${var.name}-dashboard.service"          = "api@internal"
    }
    content {
      label = labels.key
      value = labels.value
    }
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
