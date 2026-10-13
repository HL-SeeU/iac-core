#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
trap 'echo "Database backup failed at line $LINENO" >&2' ERR
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. "$script_dir/common.sh"

[[ $# -eq 2 ]] || { echo "Usage: backup-databases.sh DATABASE OUTPUT.dump" >&2; exit 1; }
require_command docker
database=$1
output=$2
validate_identifier "$database"
container=${DB_CONTAINER:-iac-core-postgres}
validate_container "$container"
[[ ! -e $output ]] || { echo "Refusing to overwrite: $output" >&2; exit 1; }
[[ -d $(dirname -- "$output") ]] || { echo "Output directory does not exist." >&2; exit 1; }
temporary=$(mktemp "${output}.tmp.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
docker exec "$container" pg_dump -U postgres -d "$database" --format=custom > "$temporary"
test -s "$temporary"
mv -n -- "$temporary" "$output"
[[ ! -e $temporary ]] || { echo "Output appeared during backup; refusing to overwrite." >&2; exit 1; }
echo "Backup written to $output."
