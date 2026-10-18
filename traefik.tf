locals {
  # Keep in sync with https://www.cloudflare.com/ips/.
  cloudflare_proxy_cidrs = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
    "2400:cb00::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2405:b500::/32",
    "2405:8100::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32",
  ]

  traefik_tcp_entrypoints = {
    mysql = 3306
  }
  traefik_dynamic_directory = "${var.host_root}/traefik/dynamic"
  traefik_dynamic_files = {
    for name in setunion(
      fileset("${path.module}/config/traefik/dynamic", "*.yml"),
      fileset("${path.module}/config/traefik/dynamic", "*.yaml"),
    ) : name => file("${path.module}/config/traefik/dynamic/${name}")
  }
}

resource "terraform_data" "traefik_files" {
  triggers_replace = [
    terraform_data.host.id,
    local.traefik_dynamic_directory,
    sha256(jsonencode(local.traefik_dynamic_files)),
    filesha256("${path.module}/scripts/sync-traefik-config.sh"),
  ]

  connection {
    type     = "ssh"
    host     = var.ssh_host
    user     = var.ssh_user
    port     = var.ssh_port
    agent    = true
    host_key = var.ssh_host_key_check ? var.ssh_host_key : ""
    timeout  = "3m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "mkdir -m 700 /tmp/iac-traefik-${self.id}",
      "mkdir -m 700 /tmp/iac-traefik-${self.id}/dynamic",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/config/traefik/dynamic/"
    destination = "/tmp/iac-traefik-${self.id}/dynamic"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/sync-traefik-config.sh"
    destination = "/tmp/iac-traefik-${self.id}/sync.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "trap 'rm -rf /tmp/iac-traefik-${self.id}' EXIT",
      "sudo -n bash /tmp/iac-traefik-${self.id}/sync.sh '/tmp/iac-traefik-${self.id}/dynamic' '${local.traefik_dynamic_directory}'",
    ]
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for name, content in local.traefik_dynamic_files :
        can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*\\.ya?ml$", name)) &&
        can(yamldecode(content))
      ])
      error_message = "Traefik dynamic files must contain valid YAML and use simple .yml/.yaml filenames."
    }
  }
}
