module "observability" {
  source = "./modules/observability"

  name_prefix          = var.name_prefix
  network              = docker_network.proxy.name
  traefik_name         = "${var.name_prefix}-traefik"
  host_root            = var.host_root
  host_revision        = terraform_data.host.id
  credentials_revision = var.credentials_revision
  grafana_cloud        = var.grafana_cloud
  grafana_cloud_token  = var.grafana_cloud_token
  ssh = {
    host     = var.ssh_host
    user     = var.ssh_user
    port     = var.ssh_port
    host_key = var.ssh_host_key_check ? var.ssh_host_key : ""
  }

  depends_on = [terraform_data.host]
}

moved {
  from = terraform_data.alloy_files
  to   = module.observability.terraform_data.alloy_files
}

moved {
  from = docker_image.alloy
  to   = module.observability.docker_image.alloy
}

moved {
  from = docker_volume.alloy
  to   = module.observability.docker_volume.alloy
}

moved {
  from = docker_container.alloy
  to   = module.observability.docker_container.alloy
}
