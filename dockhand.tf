module "dockhand" {
  source = "./modules/dockhand"

  name        = "${var.name_prefix}-dockhand"
  main_domain = var.cloudflare_main_domain
  network     = docker_network.proxy.name

  depends_on = [terraform_data.host]
}
