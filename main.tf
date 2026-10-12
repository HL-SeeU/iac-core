terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Cấu hình Terraform kết nối vào Docker trên Oracle VM qua SSH
provider "docker" {
  host = "ssh://hl@213.35.102.21:22"
}

# Triển khai thử Traefik (như đã phân tích ở trên)
resource "docker_container" "traefik" {
  name    = "traefik"
  image   = "traefik:v3.0"
  restart = "unless-stopped"

  ports {
    internal = 80
    external = 80
  }
  ports {
    internal = 443
    external = 443
  }

  # Mount docker.sock để Traefik có thể Auto-discovery các app khác
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  command = [
    "--api.insecure=true",
    "--providers.docker=true",
    "--entrypoints.web.address=:80",
    "--entrypoints.websecure.address=:443"
  ]
}