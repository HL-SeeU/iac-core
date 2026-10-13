#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Host preparation failed at line $LINENO" >&2' ERR

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
host_root=${1:?Usage: prepare-host.sh HOST_ROOT}
[[ $host_root =~ ^/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$ ]] || {
  echo "Invalid host directory." >&2; exit 1;
}
install -d -m 0755 "$host_root"
install -d -m 0700 "$host_root/secrets"
install -d -m 0700 "$host_root/secrets/apps"
echo "Host directories are ready; Terraform delivers PostgreSQL and application credential files."
