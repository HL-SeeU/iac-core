# Infisical configuration

## GitHub bootstrap credentials

The deployment workflow reads only these GitHub secrets:

| GitHub secret | Purpose |
| --- | --- |
| `INFISICAL_CLIENT_ID` | Universal-auth machine identity client ID |
| `INFISICAL_CLIENT_SECRET` | Its universal-auth client secret |
| `INFISICAL_PROJECT_SLUG` | Project slug required by `Infisical/secrets-action@v1.0.15` |

The identity needs read access to `prod`, path `/infrastructure`.
The slug is not a project UUID. Authentication inputs must exist outside the
secret store to bootstrap the loader. No GitHub Terraform/VM secrets or
configuration variables are used.

## Add these keys to Infisical

Use the exact case shown, including lowercase Terraform variable names.
Values are exported as environment variables; no `.env` file is evaluated.

Required in environment `prod`, path `/infrastructure`:

| Key | Value / purpose |
| --- | --- |
| `TERRAFORM_VERSION` | Exact supported version, e.g. `1.13.5` (Terraform >= 1.10) |
| `TF_CLOUD_ORGANIZATION` | Terraform Cloud organization |
| `TF_WORKSPACE` | The **single** workspace, e.g. `iac-core`; execution mode Local |
| `TF_TOKEN_app_terraform_io` | Terraform Cloud token authorized for this workspace |
| `TF_VAR_ssh_host` | VM IPv4 address or DNS name, without scheme/port |
| `TF_VAR_ssh_user` | Linux deploy user with passwordless sudo |
| `TF_VAR_ssh_port` | SSH port, e.g. `22` |
| `VM_SSH_PRIVATE_KEY` | Multiline OpenSSH private key, usable without an interactive passphrase |
| `SSH_KNOWN_HOSTS` | Full host key entry verified through a trusted channel |
| `TF_VAR_acme_email` | Let's Encrypt registration email |
| `TF_VAR_postgres_password` | Non-empty PostgreSQL administrator initialization password |

`SSH_KNOWN_HOSTS` must match the configured host/port; for a non-default port use
`[host]:port`. Hashed known_hosts entries are supported by OpenSSH. The runner
derives `TF_VAR_ssh_host_key` from this file, or verifies a supplied host key
against it. Do not trust an unverified `ssh-keyscan`.

Optional infrastructure configuration:

| Key | Default / purpose |
| --- | --- |
| `TF_VAR_apps` | JSON service map; defaults to `{}` |
| `TF_VAR_app_infisical_tokens` | JSON token map; defaults to `{}`, required for every enabled app |
| `TF_VAR_host_root` | `/opt/iac-core` |
| `TF_VAR_name_prefix` | `iac-core` |
| `TF_VAR_credentials_revision` | `1`; bump after rotating delivered credentials |
| `TF_VAR_ssh_host_key` | Optional explicitly pinned key matching known_hosts |
| `TF_VAR_ssh_host_key_check` | `true`; set `false` only temporarily for SSH diagnostics (disables server identity verification) |
| `TF_VAR_acme_ca_server` | Let's Encrypt staging directory URL |
| `TF_VAR_cloudflare_dns_enabled` | Set `true` to manage the proxied main-domain A record and its `www` CNAME |
| `TF_VAR_cloudflare_main_domain` | Required main domain for the Dockhand hostname and Traefik A record, e.g. `example.com` |
| `TF_VAR_cloudflare_zone_id` | 32-character Cloudflare zone ID for the main domain |
| `TF_VAR_postgres_image` | `postgres:17-bookworm` |
| `TF_VAR_database_memory_mb` | `1024` |
| `TF_VAR_database_cpus` | `1` |

When Cloudflare DNS is enabled, add `CLOUDFLARE_API_TOKEN` to this Infisical
path. Scope it to the selected zone with **Zone:DNS:Edit** and **Zone:Zone:Read**
permissions. The single A record points `cloudflare_main_domain` to the public
IPv4 in `TF_VAR_ssh_host` and is proxied by Cloudflare. A proxied CNAME maps
`www.<main-domain>` to the main domain. Another proxied CNAME maps
`dochand.<main-domain>` to the main domain. Dockhand's Traefik HTTPS route is
always enabled, independently of DNS management. Provide the main domain even
if managing DNS manually. No other app subdomain records are created; manage those
separately. Leave DNS disabled until
the domain, zone ID and token are configured.

The Traefik image defaults to `traefik:v3.6` in
`modules/traefik/variables.tf`; change that module default to select another
image. Pin a reviewed immutable digest for production.

Example `TF_VAR_apps` value (JSON, not HCL):

```json
{
  "service-a": {
    "image": "ghcr.io/your-org/service-a:1.0.0",
    "domain": "service-a.example.com",
    "port": 3000,
    "user": "1000:1000",
    "command": ["node", "server.js"],
    "memory_mb": 256,
    "cpus": 0.5,
    "infisical_project_id": "YOUR_APPLICATION_PROJECT_ID",
    "infisical_environment": "prod",
    "infisical_path": "/service-a",
    "environment": {
      "APP_ENV": "production",
      "DB_NAME": "service_a_db"
    }
  }
}
```

Corresponding `TF_VAR_app_infisical_tokens` value:

```json
{"service-a":"REPLACE_WITH_SERVICE_SCOPED_ACCESS_TOKEN"}
```

Keep real values only in Infisical. `TF_VAR_apps` must contain non-secret
configuration only; SSH host information and other ordinary inputs remain in
state. The password/token variables are `sensitive` and `ephemeral` and are used
only by file provisioners, never Terraform resource input/triggers.

## Application runtime injection

Each app image must include `/bin/sh`, `cat`, the Infisical CLI and its app
executable. Pin/review the CLI version in the service image build.

Use a service-scoped access token accepted by `infisical run` through
`INFISICAL_TOKEN`, not the raw universal-auth client secret. If tokens are
short-lived, arrange renewal in Infisical and bump `credentials_revision` before
expiry. Tokens are delivered over SSH to
`<host_root>/secrets/apps/<service-key>-token`, owned by the configured numeric
UID:GID with mode `0400`. Parent directories remain root-only.

Put `DB_USER`, `DB_PASSWORD` and application secrets in the service path, not in
the infrastructure service map. App containers fetch them at startup. Avoid
conflicting names because Infisical secrets can override non-secret environment
configuration. The module deliberately replaces the image entrypoint; include
any required image startup setup in the explicit app command.

Missing/empty tokens stop startup. Infisical errors must stop startup; do not
configure offline/cached fallback. Supply an app healthcheck to make Terraform
wait for actual application readiness.

Credential contents are not tracked for differences. After token rotation,
update `TF_VAR_credentials_revision` in Infisical and apply. This redelivers
files and recreates apps so their bind mounts see replacement file inodes.
It does not rotate an existing PostgreSQL administrator's database password;
perform that controlled SQL operation separately.

This scaffold uses the cloud Infisical endpoint. A self-hosted installation
requires changing the loader's bootstrap `domain` and consistently configuring
the host/app CLI endpoint; it cannot be discovered before the loader connects.
