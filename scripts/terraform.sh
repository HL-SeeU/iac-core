#!/usr/bin/env bash
set +x
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$script_dir/.."
source "$script_dir/runner-env.sh"
trap cleanup_runner EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
prepare_runner
# Preflight also runs for plan and other commands: existing state refresh needs Docker.
bash "$script_dir/ensure-host.sh"
terraform init -input=false -lockfile=readonly
if (( $# == 0 )); then
  set -- apply
fi
terraform "$@"
