#!/usr/bin/env bash
set -Eeuo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
export MOCK_DIR="$temporary"
mkdir "$temporary/bin"

cat > "$temporary/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$MOCK_DIR/calls"
case " $* " in
  *" pg_dump "*)
    printf 'mock-dump\n'
    exit "${MOCK_DUMP_EXIT:-0}"
    ;;
  *" pg_restore "*)
    cat > "$MOCK_DIR/restored"
    exit "${MOCK_RESTORE_EXIT:-0}"
    ;;
  *" -Atc "*)
    printf '%s\n' "${MOCK_OBJECTS:-0}"
    ;;
  *" psql "*)
    cat > "$MOCK_DIR/sql"
    ;;
  *) echo "Unexpected Docker mock call" >&2; exit 90 ;;
esac
MOCK
chmod +x "$temporary/bin/docker"
export PATH="$temporary/bin:$PATH"

expect_failure() {
  if "$@" > "$temporary/stdout" 2> "$temporary/stderr"; then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi
}

bash "$repo_root/operations/backup-databases.sh" service_a "$temporary/backup.dump"
grep -qx 'mock-dump' "$temporary/backup.dump"
expect_failure bash "$repo_root/operations/backup-databases.sh" service_a "$temporary/backup.dump"
export MOCK_DUMP_EXIT=9
expect_failure bash "$repo_root/operations/backup-databases.sh" service_a "$temporary/failed.dump"
[[ ! -e $temporary/failed.dump ]]
[[ -z $(find "$temporary" -name 'failed.dump.tmp.*' -print) ]]
unset MOCK_DUMP_EXIT
expect_failure bash "$repo_root/operations/backup-databases.sh" 'invalid;name' "$temporary/invalid.dump"

expect_failure bash "$repo_root/operations/restore-database.sh" service_a "$temporary/backup.dump"
expect_failure bash "$repo_root/operations/restore-database.sh" postgres "$temporary/backup.dump" --confirm-empty-target
export MOCK_OBJECTS=1
expect_failure bash "$repo_root/operations/restore-database.sh" service_a "$temporary/backup.dump" --confirm-empty-target
[[ ! -e $temporary/restored ]]
export MOCK_OBJECTS=0
bash "$repo_root/operations/restore-database.sh" service_a "$temporary/backup.dump" --confirm-empty-target
cmp "$temporary/backup.dump" "$temporary/restored"
grep -q -- '--exit-on-error --single-transaction' "$temporary/calls"
export MOCK_RESTORE_EXIT=7
expect_failure bash "$repo_root/operations/restore-database.sh" service_a "$temporary/backup.dump" --confirm-empty-target
! grep -q 'Restored database' "$temporary/stdout"
unset MOCK_RESTORE_EXIT

export DB_PASSWORD="dummy secret with quotes ' and spaces"
bash "$repo_root/operations/provision-databases.sh" --one service_a_db service_a
grep -q "PASSWORD %L" "$temporary/sql"
! grep -Fq "$DB_PASSWORD" "$temporary/sql"
! grep -Fq "$DB_PASSWORD" "$temporary/calls"
expect_failure bash "$repo_root/operations/provision-databases.sh" --one postgres service_a
expect_failure bash "$repo_root/operations/provision-databases.sh" --one service_a_db postgres
expect_failure bash "$repo_root/operations/provision-databases.sh" --one service_a_db pg_admin
expect_failure bash "$repo_root/operations/provision-databases.sh" --one 'bad;db' service_a
unset DB_PASSWORD
expect_failure bash "$repo_root/operations/provision-databases.sh" --one service_a_db service_a
echo "Operations regression tests passed (mock Docker, no real daemon)."
