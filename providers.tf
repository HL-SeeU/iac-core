provider "docker" {
  host                        = "ssh://${var.ssh_user}@${var.ssh_host}:${var.ssh_port}"
  disable_docker_daemon_check = true
  ssh_opts = [
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=${pathexpand(var.ssh_known_hosts_file)}",
  ]
}

provider "infisical" {}
