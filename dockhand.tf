module "dockhand" {
  source = "./modules/dockhand"

  name = "${var.name_prefix}-dockhand"

  depends_on = [terraform_data.host]
}
