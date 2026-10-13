# Architecture

## Responsibilities

| Layer | Owner |
| --- | --- |
| Existing VM, OS, SSH and firewall | VM operator |
| Docker installation and host directories | Runner preflight + root SSH provisioners |
| Images, containers, networks and volumes | Single root, Docker provider over SSH |
| Routing and certificates | Traefik flags + application Docker labels |
| Application credentials | Infisical CLI inside each application container |
| DB/user creation and credential rotation | Host-side operations scripts |
| Schema migrations | Service release pipeline |
| Host password/token file delivery | Infisical-loaded ephemeral Terraform inputs |
| State and locking | One Terraform Cloud workspace, Local execution mode |

SSH connects the runner to the **Docker host**, not to each container. Child
modules declare the same Docker provider source and inherit the root provider.
Provider daemon checking is disabled for first deployment, and all Docker
resources depend on host preparation. With existing state, Terraform refresh
still needs a working daemon before provisioners run. The runner preflight
ensures Docker exists/runs before init/apply, avoiding that refresh-order trap.

## Network boundaries

Traefik joins the proxy network. Apps join proxy and, optionally, the internal
database network. PostgreSQL joins only the internal network. Apps can reach
Infisical and external APIs through proxy; disabling `database_access` removes
the database network attachment. This shared database network is not per-service
network isolation: use separate networks/instances if that is required.

Do not enable a public Docker TCP socket. Inbound SSH must be restricted to
trusted runners/operators; HTTP/HTTPS must be reachable for HTTP-01. Docker
published ports can bypass some host firewall rules (including UFW): enforce
restrictions with the VM's cloud firewall and appropriate Docker firewall rules.

## State, persistence and secrets

Data and certificates use named Docker volumes and survive container
replacement. `prevent_destroy` blocks planned volume deletion while the resource
configuration remains present; it is not a substitute for off-host backups.
Changing PostgreSQL's major version is not an ordinary image update.

Terraform only records paths/revisions of read-only bind-mounted secret files.
Password/token file contents enter file provisioners through ephemeral variables
and are omitted from state/plans. Use bind
`mounts`, not auto-creating host-directory volumes, so a missing source file is
an error. Secret delivery runs before dependent containers are created.
Docker/host administrators can still read credentials. Socket access is
root-equivalent even with a read-only Docker socket mount; Traefik's socket mount
does not restrict API methods. A filtered socket proxy is a separate hardening
step, not included in this initial scaffold.

Infisical token material is loaded inside the container, not into the Docker
resource's environment or Terraform state. The token and injected secrets are
still accessible to sufficiently privileged processes. Runtime injection does
not automatically update an already-running app's environment: bump the
credentials revision to redeliver tokens and recreate apps after rotation.
Applications without explicit healthchecks are not waited on for
application readiness; database and Traefik healthchecks are always configured.

## Deliberately not included

- VM creation, firewall changes, automatic OS/Docker upgrades.
- Arbitrary Docker Compose conversion or a public dashboard.
- Service image builds or automatic machine-identity token issuance.
- Automatic migrations or a backup scheduler/retention policy.
- Traefik file-provider configuration: labels are sufficient for this scaffold.
  Add a reviewed file-provider mount/configuration only when needed.
