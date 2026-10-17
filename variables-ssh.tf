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

variable "ssh_host_key_check" {
  type        = bool
  default     = true
  description = "Verify SSH server identity. Disable only temporarily for connection debugging."
}

variable "ssh_host_key" {
  type        = string
  default     = ""
  description = "Verified SSH host public key. The runner derives this from SSH_KNOWN_HOSTS."
  validation {
    condition     = !var.ssh_host_key_check || can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^ ]+) [A-Za-z0-9+/=]+$", var.ssh_host_key))
    error_message = "Provide a verified SSH public host key (algorithm and base64 key)."
  }
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = "~/.ssh/known_hosts"
  ephemeral   = true
  description = "Runner-local known_hosts file; runner-env.sh sets an isolated temporary path."
}
