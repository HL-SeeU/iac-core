resource "terraform_data" "postgres_secret" {
  triggers_replace = [terraform_data.host.id, var.credentials_revision]

  connection {
    type     = "ssh"
    host     = var.ssh_host
    user     = var.ssh_user
    port     = var.ssh_port
    agent    = true
    host_key = var.ssh_host_key
    timeout  = "5m"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -m 700 /tmp/iac-secret-${self.id}"]
  }

  provisioner "file" {
    content     = var.postgres_password
    destination = "/tmp/iac-secret-${self.id}/password"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "trap 'rm -rf /tmp/iac-secret-${self.id}' EXIT",
      "sudo -n install -o root -g root -m 0600 /tmp/iac-secret-${self.id}/password '${var.host_root}/secrets/postgres-password'",
    ]
  }
}

resource "terraform_data" "app_secrets" {
  for_each = var.apps

  triggers_replace = [terraform_data.host.id, var.credentials_revision, each.value.user]

  connection {
    type     = "ssh"
    host     = var.ssh_host
    user     = var.ssh_user
    port     = var.ssh_port
    agent    = true
    host_key = var.ssh_host_key
    timeout  = "5m"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -m 700 /tmp/iac-secret-${self.id}"]
  }

  provisioner "file" {
    content     = var.app_infisical_tokens[each.key]
    destination = "/tmp/iac-secret-${self.id}/token"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "trap 'rm -rf /tmp/iac-secret-${self.id}' EXIT",
      "sudo -n install -o '${split(":", each.value.user)[0]}' -g '${split(":", each.value.user)[1]}' -m 0400 /tmp/iac-secret-${self.id}/token '${var.host_root}/secrets/apps/${each.key}-token'",
    ]
  }
}
