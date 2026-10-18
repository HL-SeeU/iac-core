# iac-core

One Terraform root, one Terraform Cloud workspace, one `terraform apply` for
container infrastructure on an **existing Ubuntu/Debian VM**.
No VM is created and no Docker Compose configuration is used.

```text
Infisical /infrastructure
  -> runner environment + isolated SSH agent
  -> SSH preflight: install Docker only if absent, prepare host
  -> terraform init
  -> terraform apply (one workspace)
       |- host preparation + ephemeral secret file provisioning
       |- proxy + internal database networks
       |- Traefik + persistent ACME volume
       |- private Dockhand admin UI + persistent data volume
       |- PostgreSQL 17 + persistent data volume
       `- reusable app containers + Infisical runtime injection
```

## Start here

1. Create **one** Terraform Cloud workspace (for example `iac-core`) and set
   **Execution Mode = Local**. Terraform Cloud stores state/locks; the runner
   executes Terraform and SSH.
2. Add the keys listed in [the Infisical configuration guide](config/infisical/README.md)
   to environment `prod`, path `/infrastructure`.
3. In GitHub, add only the loader's bootstrap secrets:
   `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`, `INFISICAL_PROJECT_SLUG`.
   These cannot be fetched from Infisical before the loader authenticates.
4. Protect the GitHub environment `production` with reviewers and branch rules.
5. Run **Terraform deployment** from Actions. It loads Infisical, installs the
   configured Terraform version, checks/installs Docker, initializes the single
   backend and invokes one `terraform apply`.

SSH IP/user/port/key, Terraform Cloud organization/workspace/API token,
PostgreSQL initialization password and app tokens all come from Infisical.
No GitHub `TF_*` or `VM_*` secrets/variables and no real tfvars file are needed.

## Local use

Requires Terraform >= 1.10, Bash, jq, OpenSSH and an authenticated Infisical CLI.
Use Linux, WSL or Git Bash for the Bash runner:

```bash
infisical run --projectId=YOUR_PROJECT_ID --env=prod --path=/infrastructure -- \
  bash scripts/terraform.sh apply
```

The wrapper performs idempotent SSH preflight and `terraform init`, then exactly
one `terraform apply`. Subsequent invocations use the same workspace.
An existing working Docker installation is not reinstalled or upgraded.

If the working directory is already initialized and the Infisical environment/
SSH agent are prepared, the native command is simply:

```bash
terraform apply
```

Native `apply` does not perform `init` or load Infisical by itself. Use the wrapper
in CI or when the daemon is missing but existing Docker resources are in state:
Terraform refresh happens before create-time provisioners.

## Dockhand administration

Terraform deploys Dockhand on the VM, always attached to the Traefik proxy
network and routed over HTTPS at `dochand.<cloudflare_main_domain>`.
Provide `TF_VAR_cloudflare_main_domain` even if managing DNS manually.
Its direct host web port remains bound only to `127.0.0.1:3000` for maintenance.
To access that maintenance port, start an SSH tunnel from your workstation:

```bash
ssh -N -L 3000:127.0.0.1:3000 -p SSH_PORT SSH_USER@SSH_HOST
```

Then open `http://127.0.0.1:3000`. On first launch, enable authentication and
create the administrator in Dockhand's **Settings > Authentication** before
using the UI. Keep the tunnel open while using it.

When Cloudflare DNS management is enabled, Terraform creates a proxied CNAME
for `dochand.<cloudflare_main_domain>`. Otherwise create its DNS record manually.
The HTTPS router to container port 3000 is always enabled.
The spelling `dochand` is intentional; its module default is `sub_domain`.
The loopback port remains available for maintenance. No IP allowlist or
external authentication middleware is added. The UI is publicly reachable when
DNS and TLS are ready; do not expose an unauthenticated installation.
For initial setup, restrict ingress externally and enable authentication through
the SSH tunnel before allowing public access. Prefer an external authentication
layer such as Cloudflare Access for production.

Traefik requests and renews certificates using its existing Let's Encrypt
HTTP-01 resolver. Allow inbound port 80 for validation and port 443 for HTTPS.
Staging certificates are not trusted: set
`TF_VAR_acme_ca_server=https://acme-v02.api.letsencrypt.org/directory`
for a publicly trusted certificate, and use Cloudflare **Full (strict)** once
the origin certificate is issued. Do not use Flexible mode or disable TLS
verification to work around certificate errors. Import existing DNS records
before applying if `dochand.<main-domain>` already exists.

Dockhand mounts the Docker socket and runs as root so it can manage containers.
This grants it effectively root-equivalent control of the VM; the read-only
socket mount does not restrict Docker API operations. Restrict access and
use a reviewed Dockhand image version for repeatable deployments. Dockhand's
BSL 1.1 license has restrictions for commercial production use; review its
[current license](https://github.com/Finsys/dockhand/blob/main/LICENSE.txt)
before deploying in that context.

## Secrets and application setup

Password/token inputs are Terraform 1.10 **ephemeral + sensitive** variables,
used only by SSH file provisioners. Secret contents are not stored in state,
saved plans, Docker resource environments or repository files.
Terraform installs the PostgreSQL password file as root `0600` and each app
token as its configured numeric UID:GID `0400`.

The initialization password only initializes an empty PostgreSQL volume.
Application DB/user creation remains a separate operation, and service
migrations remain the responsibility of each service pipeline. For a new DB,
start with `TF_VAR_apps={}`, provision DB/users, then enable the desired apps.
Both applies still use the same root/workspace. See [deployment](docs/deployment.md).

## Layout

- [host.tf](host.tf), [secrets.tf](secrets.tf): SSH host/secret provisioning.
- [main.tf](main.tf), [networks.tf](networks.tf), [providers.tf](providers.tf):
  Docker resources and module wiring.
- [modules/](modules/): Traefik, Dockhand, PostgreSQL and reusable app container.
- [scripts/](scripts/): idempotent host setup and Infisical-loaded runner.
- [operations/](operations/): DB/user provisioning, backup and restore.
- [.github/workflows/](.github/workflows/): manual deployment and offline validation.

## Offline validation

```powershell
terraform fmt -check -recursive
terraform init -backend=false -lockfile=readonly
terraform validate
terraform test
```

```bash
bash tests/operations.sh
bash tests/runner.sh
```

Tests mock Docker/SSH/runner commands and never deploy to a real VM. One
plan-only test uses the actual Docker provider with an unreachable endpoint to
check that first-deployment planning does not require an installed daemon.
Run a normal `init` before a real deployment after backend-free checks.

## Operational notes

- Only Traefik publishes ports 80/443. PostgreSQL does not publish 5432.
- ACME defaults to **staging**, whose certificates are not browser-trusted.
- Use reviewed immutable image digests for production.
- Never put secrets in app `environment`; that map is ordinary Terraform state.
- Bump `TF_VAR_credentials_revision` after rotating app tokens to deliver files
  and recreate app containers. Ephemeral values cannot be compared against state.
- DB/ACME volumes use `prevent_destroy`; keep verified off-host backups.
- If the former two workspaces were already applied, do not apply this root to
  empty state without first migrating/importing existing resources. See
  [the migration instructions](docs/deployment.md#existing-two-workspace-state).

## Guides

- [Deployment, Infisical keys and migration](docs/deployment.md)
- [Architecture and ordering constraints](docs/architecture.md)
- [Infisical credentials and runtime injection](config/infisical/README.md)
- [Backup and restore](docs/backup-restore.md)
