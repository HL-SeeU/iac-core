# Deployment

## One root and one Terraform Cloud workspace

Create one workspace such as `iac-core`, **Execution Mode = Local**, with no
VCS-triggered remote runs. The Infisical infrastructure path supplies
`TF_CLOUD_ORGANIZATION`, `TF_WORKSPACE` and `TF_TOKEN_app_terraform_io`.
Cloud stores state/locks; GitHub or your local runner executes Terraform and SSH.
Do not use Cloud workspace variables as the input source: Local execution does
not automatically load them.

The root contains host preparation, secret delivery and all Docker resources.
No `-target` or separate bootstrap apply is used.

## First deployment

1. Verify the VM SSH host key through a trusted channel. Add the full
   known_hosts entry and deployment key to Infisical. The VM user must support
   passwordless sudo. Only Ubuntu/Debian with systemd are supported.
2. Add the required infrastructure keys from
   [the exact key list](../config/infisical/README.md) to Infisical `prod`,
   `/infrastructure`. Start with `TF_VAR_apps={}` for a new PostgreSQL server.
3. Create GitHub environment `production`, require reviewers, restrict it to
   protected trusted branches, and add only the three Infisical loader bootstrap
   secrets documented in the key list.
4. Run the manual deployment workflow. It loads Infisical, installs the specified
   Terraform version and invokes `scripts/terraform.sh apply -auto-approve`.
   The wrapper:
   - validates inputs and starts an isolated SSH agent;
   - creates a private verified known_hosts file;
   - connects through SSH to install Docker only if absent and prepare directories;
   - verifies Docker access as the deploy user in a fresh SSH connection;
   - runs backend initialization and **one apply**;
   - tears down its agent and local temporary SSH files on exit.
5. Terraform's host resource also performs idempotent preparation, then copies
   the ephemeral PostgreSQL password and each configured app token through SSH.
   Password files are root `0600`; app tokens use numeric container UID:GID `0400`.
   Secret values are not passed as shell arguments or stored in state/plans.
6. PostgreSQL, Traefik, their volumes and networks are created. PostgreSQL's
   password file initializes its administrator on an empty data volume.
7. DB/user creation is still a separate provisioning layer:

   ```bash
   # On the VM, with jq + Infisical CLI installed and authorized.
   # Inject INFISICAL_TOKEN securely and set INFISICAL_PROJECT_ID.
   bash operations/provision-databases.sh config/database/services.yaml
   ```

   Each manifest path needs `DB_PASSWORD`; service `DB_USER` must match the role.
   Override `DB_CONTAINER` if `name_prefix` differs. The manifest uses JSON syntax
   (valid YAML); jq is sufficient. Existing managed roles/databases are updated,
   so do not point it at unrelated or privileged DBs/roles.
8. Enable service definitions and their token map in Infisical. Apply again in
   the **same workspace** to create the apps. Use app images containing the
   Infisical CLI, real domains, explicit startup commands and healthchecks.
   Run service migrations from the service release pipeline.
9. Point DNS to the VM and allow 80/443. Test with ACME staging, then set
   `TF_VAR_acme_ca_server=https://acme-v02.api.letsencrypt.org/directory` in
   Infisical and apply. Verify served certificates after switching; staging
   certificates are untrusted. Do not blindly delete the ACME volume.

Single apply refers to infrastructure in one root, not automatic DB/user
provisioning or service migrations. Docker dependencies wait for host setup and
secret files, not for service schemas.

## Native Terraform versus the runner

Once Infisical variables are loaded, the SSH agent/known_hosts are prepared and
the directory is initialized, use `terraform apply` at the repository root.
The host resource installs Docker if absent on the **first** deployment, and
Docker resources explicitly depend on host/secret preparation. Provider daemon
ping is disabled so provider configuration does not preempt that first setup.

For routine CI/local use, prefer:

```bash
infisical run --projectId=YOUR_PROJECT_ID --env=prod --path=/infrastructure -- \
  bash scripts/terraform.sh apply
```

Native Terraform does not load credentials or initialize an uninitialized
directory. If Docker has been removed/stopped while Docker resources remain in
state, refresh happens before provisioners: the runner's **preflight before
Terraform** is required. Disabling daemon ping does not disable resource refresh.
The preflight runs for wrapper commands including `plan`, and can install/start
Docker; native plan does not execute Terraform provisioners.

Existing Docker installations are not uninstalled/reinstalled/upgraded. An
incompatible broken installation causes an explicit failure for an operator to
repair. No public Docker TCP endpoint is enabled.

## Temporary SSH diagnostics

Host checking defaults to enabled. For a temporary diagnostic run, set
`TF_VAR_ssh_host_key_check=false` in the runner environment. This bypasses host
key matching in the runner, SSH preflight, all Terraform SSH provisioners, and
the Docker provider. The deployment private key and SSH user are still required;
`SSH_KNOWN_HOSTS` and the pinned host key are not required in this mode.
The runner emits a warning because server identity is no longer verified and
credentials could be sent to an impersonated server.

The deployment workflow currently overrides this flag to `false` for debugging.
Remove that step-level override after the test to restore verification. Do not
leave this bypass enabled for production. An authentication failure with this
flag disabled is separate from a host key mismatch.

## Secret updates and limits

- Passwords/tokens are ephemeral inputs: supply them at apply time, and at both
  plan/apply if manually using a saved plan. Do not put them in tfvars.
  The runner-local known_hosts path is also ephemeral, so each execution can
  supply its own verified temporary file rather than reuse a deleted path.
- Bump `TF_VAR_credentials_revision` after changing delivered credentials. Without
  a revision bump Terraform cannot detect that an ephemeral value changed.
- App containers are recreated on revision changes, refreshing runtime secrets
  and remounting token files. Use a planned release window; no rolling update is
  implemented on this single-host scaffold.
- The PostgreSQL password file initializes only an empty volume. Rotate an
  existing administrator through a controlled SQL operation; changing the
  Infisical value/file alone does not change the stored database password.
- Terraform data resources do not continuously inspect host file existence.
  If a secret file is removed, bump the revision to redeliver it.
- Temporary remote transfer files live in private `0700` directories, cleaned
  after successful install. Interrupted/failed transfers may leave a private
  directory; remove only the corresponding `/tmp/iac-secret-<resource-id>`
  after investigating, not arbitrary `/tmp` paths.
- Docker group/socket access is effectively root. Restrict deployment accounts,
  loader identities and runner branch permissions.
- Application `environment` and other ordinary configuration remain in state.
  Private registry authentication and automatic token issuance are not included.

## Existing two-workspace state

If the earlier layout was never applied, initialize the new workspace and deploy.
There is no old state to merge.

If either old workspace contains resources, **do not apply the new root to an
empty workspace**: that would lose existing Terraform ownership and can create
name conflicts. Freeze old CI/runs, lock access appropriately, and back up both
state snapshots securely before migration.

1. Prefer retaining the old runtime workspace as the single workspace. Runtime
   module/network addresses are unchanged (`module.database`, `module.traefik`,
   `module.apps`, `docker_network.*`), so its state already owns those resources.
2. The old bootstrap workspace owns only `terraform_data.host`, not the Docker
   daemon. Remove that tracking entry from the old bootstrap state deliberately
   (after backup, with its old configuration/workspace selected); the new root
   can recreate its idempotent host tracking in the retained workspace.
3. Select the retained workspace through Infisical, initialize at the new root,
   run preflight, inspect a plan and ensure persistent resources are not slated
   for replacement/deletion. New secret-delivery resources are expected.
4. Retire the unused workspace only after verifying the retained state and a
   successful deployment. Do not simply delete a workspace containing state.

If a differently named workspace must be used, migrate/import the full runtime
state with reviewed Terraform Cloud state tooling first; do not manually splice
state JSON or apply two owners to the same containers/volumes. Changing the VM
endpoint is also a data migration, not routine credential rotation.
