locals {
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
