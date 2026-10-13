#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Database restore failed at line $LINENO" >&2' ERR
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. "$script_dir/common.sh"

[[ $# -eq 3 && $3 == --confirm-empty-target ]] || {
  echo "Usage: restore-database.sh DATABASE INPUT.dump --confirm-empty-target" >&2; exit 1;
}
require_command docker
database=$1
input=$2
validate_identifier "$database"
[[ $database != postgres && $database != template0 && $database != template1 ]] || {
  echo "Refusing to restore into a system database." >&2; exit 1;
}
container=${DB_CONTAINER:-iac-core-postgres}
validate_container "$container"
[[ -s $input ]] || { echo "Backup file is missing or empty: $input" >&2; exit 1; }

objects=$(docker exec "$container" psql -X -v ON_ERROR_STOP=1 -U postgres -d "$database" -Atc \
  "WITH user_schemas AS (
     SELECT oid FROM pg_namespace
     WHERE nspname <> 'information_schema' AND nspname NOT LIKE 'pg_%'
   )
   SELECT
     (SELECT count(*) FROM pg_class WHERE relnamespace IN (SELECT oid FROM user_schemas)) +
     (SELECT count(*) FROM pg_proc WHERE pronamespace IN (SELECT oid FROM user_schemas)) +
     (SELECT count(*) FROM pg_type WHERE typnamespace IN (SELECT oid FROM user_schemas)) +
     (SELECT count(*) FROM pg_extension WHERE extname <> 'plpgsql');")
[[ $objects == 0 ]] || { echo "Target database must be empty." >&2; exit 1; }
docker exec -i "$container" pg_restore -U postgres -d "$database" \
  --exit-on-error --single-transaction < "$input"
echo "Restored database $database. Verify application data before enabling traffic."
