output "docker_host" {
  value       = "ssh://${var.ssh_user}@${var.ssh_host}:${var.ssh_port}"
  description = "Docker provider endpoint."
}

output "mysql_endpoint" {
  value       = "${var.ssh_host}:${local.traefik_tcp_entrypoints.mysql}"
  description = "Public TCP endpoint proxied by Traefik to the external MySQL database."
}

output "dynamic_service_urls" {
  value       = { for hostname in local.traefik_dynamic_hostnames : hostname => "https://${hostname}" }
  description = "HTTPS hostnames discovered from Traefik dynamic HTTP router rules."
}

output "database_container" {
  value       = module.database.name
  description = "Container name for host-side database operations."
}

output "database_volume" {
  value       = module.database.volume_name
  description = "Protected PostgreSQL data volume."
}

output "service_urls" {
  value       = { for name, app in var.apps : name => "https://${app.domain}" }
  description = "Traefik HTTPS routes."
}
