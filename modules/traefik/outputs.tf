output "name" {
  value = docker_container.this.name
}

output "acme_volume_name" {
  value = docker_volume.acme.name
}
