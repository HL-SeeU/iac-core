output "name" {
  value = docker_container.this.name
}

output "volume_name" {
  value = docker_volume.data.name
}
