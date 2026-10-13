resource "docker_network" "proxy" {
  name       = "${var.name_prefix}-proxy"
  depends_on = [terraform_data.host]
}

resource "docker_network" "database" {
  name       = "${var.name_prefix}-database"
  internal   = true
  depends_on = [terraform_data.host]
}
