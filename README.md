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

## Traefik dashboard

The dashboard is routed over HTTPS at
`https://proxy.<cloudflare_main_domain>/dashboard/` (including the trailing `/`).
Both the dashboard and API are publicly accessible without authentication.
HTTPS encrypts traffic but does not restrict access. Use external access
controls if these endpoints must be private. The insecure API listener remains
disabled; port 8080 is not published.

No dashboard credentials are required. Remove the former
`TF_VAR_traefik_dashboard_users` secret from Infisical if upgrading from the
Basic Auth configuration. After applying, the former users file at
`<host_root>/secrets/traefik-dashboard-users` is no longer mounted or managed;
it can be removed manually from the VM.

With Cloudflare DNS enabled, Terraform creates the proxied `proxy` CNAME;
otherwise create the DNS record manually. Use a production Let's Encrypt
certificate and Cloudflare Full (strict) as described below for Dockhand.

## HTTPS rate limiting

All HTTP routers on Traefik's `websecure` entrypoint, including the dashboard
and Dockhand, inherit a rate-limit middleware: average **100 requests/second**
per client IP, with a token-bucket capacity (`burst`) of **200**. Excess requests
receive HTTP **429**. This is a default policy per router, not a shared global
quota across all services. Router-specific middleware can add tighter limits.
TCP listeners such as MySQL and the HTTP-to-HTTPS redirect are unchanged.

The root deployment assumes **Cloudflare proxy -> Traefik** with no additional
proxy hop. It trusts forwarded headers only from the Cloudflare IPv4/IPv6 CIDRs
in [traefik.tf](traefik.tf), and selects the rightmost `X-Forwarded-For` address
for rate limiting. Keep these ranges synchronized with
[Cloudflare's published list](https://www.cloudflare.com/ips/). Do not enable
insecure forwarded-header trust. If the proxy chain changes (for example, to
Cloudflare Tunnel), review both trusted CIDRs and the IP-selection strategy.

This does not restrict origin access: direct, untrusted requests have forwarded
headers stripped and, with the one-hop strategy, share the empty-IP bucket.
Restrict origin web access to Cloudflare at the firewall to prevent bypassing
its edge protection; review ACME HTTP-01 reachability before doing so. Reusable
module callers without `trusted_proxy_cidrs` use the connection IP instead.
Rate limiting is not volumetric DDoS protection or dashboard authentication.

Applying the new entrypoint arguments recreates Traefik and briefly interrupts
proxy traffic. After deployment, verify real client IP separation and HTTP 429
responses through Cloudflare, and monitor application latency and resource use.
Local configuration checks:
`terraform test -filter=tests/traefik-ratelimit.tftest.hcl`.

## Webmin on the Docker host

The existing host Webmin service is routed at `https://webmin.seeu.pro.vn`.
[webmin.yml](config/traefik/dynamic/webmin.yml) is a static configuration,
copied with the other dynamic YAML files using the same directory sync as MySQL.
With Cloudflare DNS enabled, Terraform discovers the hostname from its `Host`
rule and creates a proxied CNAME; `dynamic_service_urls` lists discovered URLs.
If changing the main domain, update the hostname in `webmin.yml` too.

Traefik maps `host.docker.internal` to Docker's `host-gateway` and forwards to
`https://host.docker.internal:10000`. Docker Engine 20.10+ is required. This
does not add a network, enable host networking, or publish port 10000.
The first deployment recreates Traefik and briefly interrupts proxy traffic.

Webmin must already listen on an address reachable from the container, not
only `127.0.0.1`. Restrict port 10000 to the necessary Docker sources with
host/cloud firewalls; do not expose it publicly. Host Webmin installation,
listen addresses and referer settings are not managed by Terraform.
If required by Webmin, add `webmin.<cloudflare_main_domain>` to its existing
`referers` setting and restart Webmin.

The Webmin-only servers transport skips backend certificate verification to
support its self-signed HTTPS certificate; other services are unaffected.
Use a trusted backend certificate/CA instead where possible. Protect this
administration endpoint with external access controls and Webmin login/2FA.
Verify the login page and redirects after applying, and use a production ACME
certificate with Cloudflare Full (strict).

Local checks: `terraform test -filter=tests/webmin.tftest.hcl`.

## External MySQL TCP proxy

The root configures Traefik to forward `<ssh_host>:3306` to the existing OCI
database at `10.0.0.91:3306`. The `mysql_endpoint` output shows the client endpoint.
This is separate from the internal PostgreSQL container and does not change
HTTP/HTTPS routes. The reusable Traefik module contains no MySQL-specific
configuration; its additional listeners and file provider are disabled by default.

### Adding ports and services

- Define additional TCP entrypoints in `local.traefik_tcp_entrypoints` in
  [traefik.tf](traefik.tf). The module generates both listener arguments and
  Docker port mappings from this map. For example, add `redis = 6379` alongside
  `mysql = 3306`; built-in entrypoint names and ports are reserved.
- Add or edit top-level `.yml`/`.yaml` files in
  [config/traefik/dynamic](config/traefik/dynamic). These are standard Traefik
  dynamic configurations and can contain TCP or HTTP routers/services.
  [mysql.yml](config/traefik/dynamic/mysql.yml) defines the current MySQL backend.
  Each router must reference an existing entrypoint, and router/service names
  must be unique across files.
- Run the normal Terraform deployment. Root provisioning uploads the files over
  SSH into `<host_root>/traefik/dynamic` before Traefik starts. That directory is
  reserved for these managed YAML files: removed repository files are removed
  from the VM on the next apply. Keep secrets out of this configuration.

With Cloudflare DNS enabled, exact backtick HTTP matchers such as
``Host(`app.seeu.pro.vn`)`` automatically create proxied CNAME records pointing
to `cloudflare_main_domain`. Declare each hostname only in YAML; no separate
DNS resource is needed. Multiple `Host` matchers are supported, names are
lowercased and duplicates are removed. Hostnames must be valid subdomains of
`cloudflare_main_domain`; other domains fail the plan. `HostRegexp`, TCP
`HostSNI`, and rules without an exact backtick `Host` matcher do not create DNS.
The main domain, `www`, Dockhand and the dashboard retain their separate DNS
resources and are excluded from automatic creation. This discovery only covers
dynamic YAML files, not Docker labels or `var.apps`. Removing a hostname from
all dynamic routers removes its automatic DNS record on the next apply.
Import any pre-existing manually managed record before applying.

The module mounts the entire directory read-only and enables file-provider
watching. Backend/router changes are synchronized using atomic per-file renames
without replacing the mounted directory, allowing Traefik to reload without
container replacement. Unchanged files are not rewritten. Updates spanning
multiple files are not transactional; keep tightly coupled routes/services in
one file. YAML syntax is checked at plan time; validate actual routing after
deployment because syntax validation does not verify all Traefik semantics.

Changing entrypoints or published ports still recreates Traefik and briefly
interrupts proxy traffic. Migrating from the former embedded MySQL configuration
also recreates Traefik once to switch to the directory provider. No manual file
creation on the VM is required. Ensure new host ports are not already in use and
open their OCI ingress rules separately.

Local checks: `terraform test -filter=tests/mysql-proxy.tftest.hcl` and
`bash tests/traefik-config.sh` (Linux, WSL or Git Bash).

Allow inbound TCP destination port 3306 to the VM in its OCI NSG/Security List
and any applicable host/container firewall rules. Allow the VM to reach the
database on TCP 3306. A successful `nc -vz 10.0.0.91 3306` on the VM verifies
host connectivity; the Traefik Docker network must also have outbound access.
The listener binds to all IPv4 host interfaces, not `ssh_host`: OCI public IPs
are normally NAT mappings rather than addresses assigned to the Linux interface.

From an external client, test the complete path with:

```bash
mysql --protocol=TCP --host=VM_PUBLIC_IP --port=3306 --user=DB_USER --password
```

Use the database's existing credentials and grants, then run `SELECT 1;`.
Traefik forwards raw TCP without TLS termination; MySQL TLS, if configured,
is negotiated directly between the client and database. No HTTP routing or
Let's Encrypt certificate is involved. Use the VM public IP directly or a
DNS-only record, not a standard Cloudflare-proxied record.

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

## Grafana Cloud observability (optional)

Traefik metrics, access logs and traces can be sent through a private Grafana
Alloy container to **Grafana Cloud Free**. No Grafana, Prometheus, Loki or Tempo
server is hosted on the VM. Existing deployments remain unchanged until
`TF_VAR_grafana_cloud` is configured in Infisical; see the
[connection keys](config/infisical/README.md#optional-grafana-cloud).

The [observability module](modules/observability/) owns Alloy provisioning,
configuration, storage and credential delivery. The root only passes Infisical
inputs and wires its internal tracing endpoint to Traefik. Cloud validation
lives in the module; root variables remain necessary for `TF_VAR_*` inputs.
State `moved` blocks preserve the former root resource addresses without
requiring a manual `terraform state mv` during this extraction. Container and
volume names, the rendered configuration and credential paths are unchanged.

Create a Grafana Cloud stack on the Free plan and copy its Prometheus
remote-write URL/user, Loki push URL/user and OpenTelemetry HTTP base URL/user
from the Cloud connection pages. Create a stack-scoped access-policy token
with only `metrics:write`, `logs:write` and `traces:write`. Store it in
Infisical, not in tfvars, Docker environment variables or Git. Run the normal
deployment after adding the connection keys. Bump `TF_VAR_credentials_revision`
when rotating the token; this redelivers the root-only file and recreates Alloy.

### Free quota versus collection controls

Use the allowances shown in your own Cloud account as authoritative:

| Allowance | Meaning | Repository collection policy |
| --- | --- | --- |
| 10k active metric series | Distinct metric name + label combinations active in Cloud, not log lines or samples | One Traefik target, router labels disabled, metric allowlists, 60-second scrape interval |
| 14-day retention | Cloud controls how long data remains queryable; this does not reset monthly usage every 14 days | No local retention setting can increase the Free retention |
| 50 GB processed/written/retained, where listed | Separate product-specific usage dimensions, not a combined 150 GB pool | Reduce data before export; verify the product and billing period for each allowance in Cloud |

The metrics scrape safety limits are 7,500 raw samples for Traefik and 1,500
for Alloy per scrape. Exceeding a limit **fails that scrape**, rather than
keeping the first N series. These limits do not guarantee fewer than 10k
Cloud-active series: label churn, scrape-generated metrics, and other senders
also count. Slower scraping reduces samples, not the number of active series.

Access logs keep status, duration, method, router/service names, timestamp and
trace/span IDs only; paths, query strings, client IPs and headers are omitted.
Alloy keeps errors (HTTP >= 400) and slow requests (>= 1 second), samples 10%
of other requests, then applies a **shared 2 lines/second, burst 10** limit.
Lines over 4 KB are dropped. Errors and slow requests can also be dropped
during overload. At a sustained 2 x 4 KB/second this is roughly 22 GB of raw
lines per 31 days, excluding metadata, retries, restart bursts and other
senders. This is a conservative estimate, **not a Cloud monthly hard cap**.
Traefik still writes all allowlisted access logs locally; Docker rotation is
10 MB x 3 files. General Traefik operational logs remain in Docker, not Loki.

Tracing samples 10% of root traces at Traefik; incoming parent sampling
decisions are respected. This is not a byte limit, and externally sampled
parents can increase the volume. Application internals require application
OpenTelemetry instrumentation. Alloy uses bounded trace queues and a memory
limiter; these protect the VM, not the Cloud quota.

Stay on the **Free** plan if you do not want paid overage billing; do not treat
these source controls as a billing cap on a paid plan. In Grafana, check
**Billing/Usage** and the `grafanacloud-usage` data source, and configure
usage alerts at 70/85/95% of the applicable allowances. Alerts notify; they do
not stop export. Check `up{job="traefik"}` and `up{job="alloy"}` for scrape
failures and Alloy's forwarded drop/exporter metrics for data loss.

Verify after deployment:

- Import the [Traefik dashboard 17346](https://grafana.com/grafana/dashboards/17346/);
  router-level panels may be empty because router metrics are disabled.
- In Explore, query metrics `traefik_service_requests_total` and Loki
  `{job="traefik"}`. Low traffic and sampling can mean no normal-request logs.
- In Tempo, search for service `<name_prefix>-traefik`; make enough requests
  to produce sampled traces. Trace IDs in sampled access logs can be used to
  look up traces.
- Inspect Alloy readiness and errors with `docker inspect` / `docker logs`.
  Readiness confirms the local configuration, not successful Cloud delivery;
  check for authentication, rate-limit and export errors too.

Alloy has no host-published ports or Traefik route. Its administration server
binds to container loopback; OTLP port 4318 and Traefik metrics port 8082 are
only reachable on the Docker proxy network. Root-only Cloud credentials are
directory-mounted read-only. Alloy reads Traefik logs through the Docker
socket: even a read-only mount grants root-equivalent Docker API access.
Only trusted workloads should share this network. The persistent Alloy
volume holds log positions and the metrics WAL, not 14 days of telemetry;
long Cloud outages can lose data, and the volume still needs disk monitoring.
Removing `TF_VAR_grafana_cloud` stops collection on the next apply; it does not
erase existing Cloud data or the root-only host credential file. Revoke the
Cloud token and remove the unused credential file when retiring the integration.

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
- [modules/](modules/): Traefik, Dockhand, PostgreSQL, observability and reusable app container.
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

With Python 3 and a local Docker daemon, also run `python tests/observability.py`.
It validates the rendered Alloy configuration and tests metrics filtering,
log sampling/rate limits and trace export against fake endpoints on an isolated
Docker network. It pulls the pinned Alloy and Python test images if absent,
never contacts Grafana Cloud, and removes its own containers/network afterward.

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
