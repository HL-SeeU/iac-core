terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6.2"
    }
  }

  required_providers {
    infisical = {
      source = "infisical/infisical"
      version = "~> 0.12.0"
    }
  }
}
