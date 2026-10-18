variable "traefik_dashboard_users" {
  type        = string
  sensitive   = true
  ephemeral   = true
  description = "Infisical-loaded htpasswd content: one username:bcrypt-hash per line."
  validation {
    condition = (
      length(trimspace(var.traefik_dashboard_users)) > 0 &&
      alltrue([
        for line in split("\n", trimspace(var.traefik_dashboard_users)) :
        can(regex("^[^:\\s]+:\\$2[aby]\\$(0[4-9]|[12][0-9]|3[01])\\$[./A-Za-z0-9]{53}$", trimsuffix(line, "\r")))
      ])
    )
    error_message = "Supply non-empty htpasswd bcrypt entries in TF_VAR_traefik_dashboard_users, one username:hash per line."
  }
}
