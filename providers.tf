provider "docker" {
  host                        = "ssh://${var.ssh_user}@${var.ssh_host}:${var.ssh_port}"
  disable_docker_daemon_check = true
  ssh_opts = [
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=${var.ssh_host_key_check ? "yes" : "no"}",
    "-o", "UserKnownHostsFile=${var.ssh_host_key_check ? pathexpand(var.ssh_known_hosts_file) : "/dev/null"}",
    "-o", "GlobalKnownHostsFile=/dev/null",
  ]
}

provider "infisical" {}

provider "cloudflare" {}
