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
- [modules/](modules/): Traefik, PostgreSQL and reusable app container.
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
