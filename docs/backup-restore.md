# PostgreSQL backup and restore

Run the operations scripts on the Docker host as an authorized Docker operator.
They use `docker exec` and local PostgreSQL administrator authentication, without
publishing a DB port or retrieving the administrator password for these scripts.
The scripts require Bash and the Docker CLI; provisioning additionally needs
`jq` and the Infisical CLI. PostgreSQL client binaries come from the DB image.

## Backup

```bash
mkdir -p backups
DB_CONTAINER=iac-core-postgres \
  bash operations/backup-databases.sh service_a_db backups/service_a.dump
```

The script writes a custom-format `pg_dump` to a private temporary file, then
publishes it only on success. Existing files are not overwritten. Back up each
database separately. Dumps contain application data and must be encrypted,
copied off-host, access-controlled and retained according to your recovery
requirements. A file on the same VM is not a disaster-recovery backup.

This does not back up global PostgreSQL roles, Infisical secrets, Docker volumes,
Terraform Cloud state or Traefik ACME data. Recreate managed DB roles from the
manifest and Infisical credentials before restoring. Maintain separate,
encrypted backups of ACME/state and a tested secret recovery process.

Schedule backups externally (for example with a reviewed systemd timer), monitor
failures, and routinely restore to an isolated instance to measure RPO/RTO.

## Restore

1. Stop affected application writers and migrations; take a fresh backup if the
   old database is still accessible.
2. Provision the target DB and owner using the reviewed manifest. Restore only
   into an **empty** target. This script does not drop, clean or recreate a DB.
3. Ensure original dump owner roles exist. Use only trusted dumps: PostgreSQL
   restores can execute SQL from the archive with administrator privileges.
4. Run:

   ```bash
   DB_CONTAINER=iac-core-postgres \
     bash operations/restore-database.sh service_a_db backups/service_a.dump --confirm-empty-target
   ```

5. Verify owners, grants, row counts, service migrations and application health
   before resuming traffic.

The script refuses a non-empty target and runs `pg_restore` with
`--exit-on-error --single-transaction`; failed restores roll back their changes.
Check PostgreSQL client/server compatibility before restoring across versions.
PostgreSQL major-version upgrades need a documented `pg_upgrade` or dump/restore
procedure; changing the Terraform image variable is not such a procedure.
