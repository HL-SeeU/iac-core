resource "terraform_data" "host" {
  triggers_replace = [
    var.ssh_host,
    var.ssh_user,
    var.ssh_port,
    var.ssh_host_key,
    var.host_root,
    filesha256("${path.module}/scripts/install-docker.sh"),
    filesha256("${path.module}/scripts/prepare-host.sh"),
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
    inline = ["mkdir -m 700 /tmp/iac-bootstrap-${self.id}"]
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-docker.sh"
    destination = "/tmp/iac-bootstrap-${self.id}/install-docker.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/prepare-host.sh"
    destination = "/tmp/iac-bootstrap-${self.id}/prepare-host.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "trap 'rm -rf /tmp/iac-bootstrap-${self.id}' EXIT",
      "sudo -n bash /tmp/iac-bootstrap-${self.id}/install-docker.sh '${var.ssh_user}'",
      "sudo -n bash /tmp/iac-bootstrap-${self.id}/prepare-host.sh '${var.host_root}'",
      "sudo -n docker info >/dev/null",
    ]
  }
}
