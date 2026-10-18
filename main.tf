module "traefik" {
  source = "./modules/traefik"

  name           = "${var.name_prefix}-traefik"
  network        = docker_network.proxy.name
  acme_email     = var.acme_email
  acme_ca_server = var.acme_ca_server
  main_domain    = var.cloudflare_main_domain

  depends_on = [terraform_data.host]
}

module "database" {
  source = "./modules/database"

  name               = local.database_name
  image              = var.postgres_image
  network            = docker_network.database.name
  password_file_path = "${var.host_root}/secrets/postgres-password"
  memory_mb          = var.database_memory_mb
  cpus               = var.database_cpus

  depends_on = [terraform_data.postgres_secret]
}

module "apps" {
  for_each = var.apps
  source   = "./modules/app-container"

  name        = "${var.name_prefix}-${each.key}"
  image       = each.value.image
  memory_mb   = each.value.memory_mb
  cpus        = each.value.cpus
  user        = each.value.user
  command     = each.value.command
  healthcheck = each.value.healthcheck
  networks = concat(
    [docker_network.proxy.name],
    each.value.database_access ? [docker_network.database.name] : [],
  )
  environment = merge(
    each.value.database_access ? { DB_HOST = local.database_name } : {},
    each.value.environment,
  )
  infisical_project_id  = each.value.infisical_project_id
  infisical_environment = each.value.infisical_environment
  infisical_path        = each.value.infisical_path
  infisical_token_path  = "${var.host_root}/secrets/apps/${each.key}-token"
  secret_revision       = var.credentials_revision

  labels = {
    "traefik.enable"                                             = "true"
    "traefik.docker.network"                                     = docker_network.proxy.name
    "traefik.http.routers.${each.key}.rule"                      = "Host(`${each.value.domain}`)"
    "traefik.http.routers.${each.key}.entrypoints"               = "websecure"
    "traefik.http.routers.${each.key}.tls"                       = "true"
    "traefik.http.routers.${each.key}.tls.certresolver"          = "letsencrypt"
    "traefik.http.routers.${each.key}.service"                   = each.key
    "traefik.http.services.${each.key}.loadbalancer.server.port" = tostring(each.value.port)
  }

  depends_on = [terraform_data.app_secrets, module.database, module.traefik]
}
