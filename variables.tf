variable "ssh_host" {
  type        = string
  description = "IPv4 address or DNS name of the Docker host."
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*$", var.ssh_host))
    error_message = "Use an IPv4 address or DNS name without a scheme or port."
  }
}

variable "ssh_user" {
  type        = string
  description = "SSH user with passwordless sudo; Docker group access is prepared automatically."
  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*$", var.ssh_user))
    error_message = "ssh_user must be a valid Linux username."
  }
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535 && floor(var.ssh_port) == var.ssh_port
    error_message = "ssh_port must be an integer between 1 and 65535."
  }
}

variable "host_root" {
  type        = string
  default     = "/opt/iac-core"
  description = "Host directory for automatically provisioned secret files."
  validation {
    condition     = can(regex("^/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$", var.host_root))
    error_message = "Use an absolute path containing only letters, digits, underscores and hyphens."
  }
}

variable "name_prefix" {
  type        = string
  default     = "iac-core"
  description = "Prefix for Docker containers, networks and volumes."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "Use lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "acme_email" {
  type        = string
  description = "Email for Let's Encrypt account registration."
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.acme_email))
    error_message = "Provide a valid email address."
  }
}

variable "acme_ca_server" {
  type        = string
  default     = "https://acme-staging-v02.api.letsencrypt.org/directory"
  description = "Defaults to staging; switch explicitly to production after testing DNS and HTTP-01."
}

variable "traefik_image" {
  type        = string
  default     = "traefik:v3.6"
  description = "Traefik image; pin to a reviewed digest for production."
}

variable "postgres_image" {
  type        = string
  default     = "postgres:17-bookworm"
  description = "PostgreSQL 17 image; major version upgrades require a separate migration."
}

variable "database_memory_mb" {
  type        = number
  default     = 1024
  description = "PostgreSQL memory limit in MB."
  validation {
    condition     = var.database_memory_mb >= 128 && floor(var.database_memory_mb) == var.database_memory_mb
    error_message = "Database memory must be an integer of at least 128 MB."
  }
}

variable "database_cpus" {
  type        = number
  default     = 1
  description = "PostgreSQL CPU quota."
  validation {
    condition     = var.database_cpus > 0
    error_message = "Database CPU quota must be positive."
  }
}

variable "apps" {
  description = "Service definitions. Environment must contain only non-secret configuration."
  type = map(object({
    image                 = string
    domain                = string
    port                  = number
    command               = list(string)
    user                  = string
    memory_mb             = optional(number, 256)
    cpus                  = optional(number, 0.5)
    environment           = optional(map(string), {})
    database_access       = optional(bool, true)
    infisical_project_id  = string
    infisical_environment = optional(string, "prod")
    infisical_path        = string
    healthcheck           = optional(list(string))
  }))
  default = {}
  validation {
    condition = alltrue([
      for name, app in var.apps :
      can(regex("^[a-z][a-z0-9-]*$", name)) &&
      can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*\\.[A-Za-z]{2,}$", app.domain)) &&
      app.port >= 1 && app.port <= 65535 && floor(app.port) == app.port &&
      app.memory_mb >= 16 && floor(app.memory_mb) == app.memory_mb && app.cpus > 0 &&
      length(app.command) > 0 && alltrue([for arg in app.command : length(arg) > 0]) &&
      can(regex("^[0-9]+:[0-9]+$", app.user)) && length(app.infisical_project_id) > 0 &&
      startswith(app.infisical_path, "/") &&
      (app.healthcheck == null ? true : length(app.healthcheck) > 0)
    ])
    error_message = "Each app needs a valid name/domain/port, positive limits, command, numeric UID:GID, Infisical project/path, and a non-empty healthcheck if specified."
  }

  validation {
    condition     = length(distinct([for app in values(var.apps) : app.domain])) == length(var.apps)
    error_message = "App domains must be unique."
  }
}

variable "ssh_host_key" {
  type        = string
  description = "Verified SSH host public key. The runner derives this from SSH_KNOWN_HOSTS."
  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^ ]+) [A-Za-z0-9+/=]+$", var.ssh_host_key))
    error_message = "Provide a verified SSH public host key (algorithm and base64 key)."
  }
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = "~/.ssh/known_hosts"
  ephemeral   = true
  description = "Runner-local known_hosts file; runner-env.sh sets an isolated temporary path."
}

variable "postgres_password" {
  type        = string
  sensitive   = true
  ephemeral   = true
  description = "Infisical-loaded administrator password, used only by the SSH file provisioner."
  validation {
    condition     = length(trimspace(var.postgres_password)) > 0
    error_message = "Load a non-empty TF_VAR_postgres_password from Infisical."
  }
}

variable "app_infisical_tokens" {
  type        = map(string)
  default     = {}
  sensitive   = true
  ephemeral   = true
  description = "Infisical-loaded service tokens keyed by app name; never persisted in state or plans."
  validation {
    condition = alltrue([
      for name in keys(var.apps) :
      try(length(trimspace(var.app_infisical_tokens[name])) > 0, false)
    ])
    error_message = "TF_VAR_app_infisical_tokens must contain a non-empty token for every configured app."
  }
}

variable "credentials_revision" {
  type        = string
  default     = "1"
  description = "Bump after credential rotation to redeliver files and recreate app containers."
  validation {
    condition     = length(trimspace(var.credentials_revision)) > 0
    error_message = "credentials_revision must not be empty."
  }
}
