module "dockhand" {
  source = "./modules/dockhand"

  name      = "${var.name_prefix}-dockhand"
  image     = var.dockhand_image
  memory_mb = var.dockhand_memory_mb
  cpus      = var.dockhand_cpus

  depends_on = [terraform_data.host]
}
