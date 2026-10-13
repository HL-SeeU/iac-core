#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Database provisioning failed at line $LINENO" >&2' ERR
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. "$script_dir/common.sh"

require_command docker
export DB_CONTAINER=${DB_CONTAINER:-iac-core-postgres}
validate_container "$DB_CONTAINER"

if [[ ${1:-} == --one ]]; then
  [[ $# -eq 3 ]] || { echo "Usage: provision-databases.sh --one DATABASE ROLE" >&2; exit 1; }
  export DB_NAME=$2 DB_ROLE=$3
  validate_identifier "$DB_NAME"
  validate_identifier "$DB_ROLE"
  [[ $DB_ROLE != postgres && $DB_ROLE != pg_* ]] || {
    echo "Refusing to modify a reserved role." >&2; exit 1;
  }
  [[ $DB_NAME != postgres && $DB_NAME != template0 && $DB_NAME != template1 ]] || {
    echo "Refusing to provision a system database." >&2; exit 1;
  }
  : "${DB_PASSWORD:?Inject DB_PASSWORD from Infisical}"
  export DB_PASSWORD

  # psql quotes values/identifiers; password values never enter CLI arguments.
  docker exec -i -e DB_NAME -e DB_ROLE -e DB_PASSWORD "$DB_CONTAINER" \
    psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
\getenv db_name DB_NAME
\getenv db_role DB_ROLE
\getenv db_password DB_PASSWORD
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION', :'db_role')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'db_role') \gexec
SELECT format('ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L', :'db_role', :'db_password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_role')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name') \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'db_role') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'db_name') \gexec
SQL
  echo "Provisioned database $DB_NAME for role $DB_ROLE."
  exit 0
fi

[[ $# -le 1 ]] || { echo "Usage: provision-databases.sh [MANIFEST]" >&2; exit 1; }
require_command jq
require_command infisical
: "${INFISICAL_PROJECT_ID:?Set INFISICAL_PROJECT_ID}"
: "${INFISICAL_TOKEN:?Authenticate the host-side Infisical CLI using INFISICAL_TOKEN}"
manifest=${1:-"$script_dir/../config/database/services.yaml"}

# JSON is a YAML subset; keeping this manifest in JSON avoids a YAML parser dependency.
jq -e '
  .services as $s |
  ($s | type == "array" and length > 0) and
  all($s[];
    (.database | type == "string" and test("^[a-z_][a-z0-9_]{0,62}$")) and
    (.role | type == "string" and test("^[a-z_][a-z0-9_]{0,62}$")) and
    (.infisical_path | type == "string" and startswith("/") and (test("[\t\r\n]") | not))
  ) and
  ($s | map(.database) | unique | length) == ($s | length) and
  ($s | map(.role) | unique | length) == ($s | length)
' "$manifest" >/dev/null
rows=$(jq -r '.services[] | [.database, .role, .infisical_path] | @tsv' "$manifest")

while IFS=$'\t' read -r database role secret_path; do
  infisical run --projectId="$INFISICAL_PROJECT_ID" --env="${INFISICAL_ENVIRONMENT:-prod}" \
    --path="$secret_path" -- bash "$script_dir/provision-databases.sh" --one "$database" "$role"
done <<< "$rows"
