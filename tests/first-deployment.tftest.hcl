run "plan_without_a_docker_daemon" {
  command = plan
  variables {
    cloudflare_dns_enabled = false
    cloudflare_main_domain = "local.io.vn"
    ssh_host               = "127.0.0.1"
    ssh_user               = "deploy"
    ssh_port               = 1
    ssh_host_key           = "ssh-ed25519 dGVzdA=="
    acme_email             = "ops@example.com"
    postgres_password      = "ephemeral-plan-only-password"
  }
  assert {
    condition     = docker_network.database.internal && output.database_container == "iac-core-postgres"
    error_message = "A first-deployment plan must succeed before Docker exists."
  }
}
