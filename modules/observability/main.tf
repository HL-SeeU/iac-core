locals {
  observability_enabled = var.grafana_cloud != null
  alloy_name            = "${var.name_prefix}-alloy"
  alloy_config = local.observability_enabled ? templatefile("${path.module}/config.alloy.tftpl", {
    cloud        = var.grafana_cloud
    traefik_name = var.traefik_name
    instance     = var.name_prefix
  }) : ""
}

resource "terraform_data" "alloy_files" {
  count = local.observability_enabled ? 1 : 0
  triggers_replace = [
    var.host_revision,
    var.credentials_revision,
    sha256(local.alloy_config),
  ]

  connection {
    type     = "ssh"
    host     = var.ssh.host
    user     = var.ssh.user
    port     = var.ssh.port
    agent    = true
    host_key = var.ssh.host_key
    timeout  = "5m"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -m 700 /tmp/iac-alloy-${self.id}"]
  }

  provisioner "file" {
    content     = local.alloy_config
    destination = "/tmp/iac-alloy-${self.id}/config.alloy"
  }

  provisioner "file" {
    content     = trimspace(var.grafana_cloud_token)
    destination = "/tmp/iac-alloy-${self.id}/cloud-token"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "trap 'rm -rf /tmp/iac-alloy-${self.id}' EXIT",
      "sudo -n install -d -o root -g root -m 0700 '${var.host_root}/observability'",
      "sudo -n install -o root -g root -m 0600 /tmp/iac-alloy-${self.id}/config.alloy '${var.host_root}/observability/config.alloy'",
      "sudo -n install -o root -g root -m 0600 /tmp/iac-alloy-${self.id}/cloud-token '${var.host_root}/observability/cloud-token'",
    ]
  }
}

resource "docker_image" "alloy" {
  count        = local.observability_enabled ? 1 : 0
  name         = "grafana/alloy:v1.20.1"
  keep_locally = true
}

resource "docker_volume" "alloy" {
  count = local.observability_enabled ? 1 : 0
  name  = "${local.alloy_name}-data"
}

resource "docker_container" "alloy" {
  count   = local.observability_enabled ? 1 : 0
  name    = local.alloy_name
  image   = docker_image.alloy[0].image_id
  restart = "unless-stopped"
  user    = "0:0"
  memory  = 512
  cpus    = "0.5"
  env     = []

  command = [
    "run",
    "--server.http.listen-addr=127.0.0.1:12345",
    "--storage.path=/var/lib/alloy/data",
    "--disable-reporting",
    "/etc/alloy/config.alloy",
  ]

  mounts {
    type      = "bind"
    source    = "${var.host_root}/observability"
    target    = "/etc/alloy"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = "/var/run/docker.sock"
    target    = "/var/run/docker.sock"
    read_only = true
  }

  volumes {
    volume_name    = docker_volume.alloy[0].name
    container_path = "/var/lib/alloy/data"
  }

  networks_advanced {
    name = var.network
  }

  labels {
    label = "traefik.enable"
    value = "false"
  }

  healthcheck {
    test = [
      "CMD", "/usr/bin/bash", "-ec",
      "exec 3<>/dev/tcp/127.0.0.1/12345; printf 'GET /-/ready HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n' >&3; IFS= read -r status <&3; [[ \"$status\" == *' 200 '* ]]",
    ]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "30s"
  }

  wait         = true
  wait_timeout = 120
  log_driver   = "json-file"
  log_opts     = { "max-size" = "10m", "max-file" = "3" }

  depends_on = [terraform_data.alloy_files]

  lifecycle {
    replace_triggered_by = [terraform_data.alloy_files]
  }
}
