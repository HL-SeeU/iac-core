#!/usr/bin/env bash
set +x
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
: "${SSH_AUTH_SOCK:?Run prepare_runner first}"
: "${SSH_AGENT_PID:?Run prepare_runner first}"
: "${TF_VAR_ssh_known_hosts_file:?Run prepare_runner first}"
: "${TF_VAR_ssh_host:?Missing SSH host}"
: "${TF_VAR_ssh_user:?Missing SSH user}"
: "${TF_VAR_ssh_port:?Missing SSH port}"
: "${TF_VAR_host_root:?Missing host directory}"
[[ -f $TF_VAR_ssh_known_hosts_file ]]
[[ $TF_VAR_ssh_host =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]
[[ $TF_VAR_ssh_user =~ ^[a-z_][a-z0-9_-]*$ ]]
[[ $TF_VAR_ssh_port =~ ^[0-9]{1,5}$ ]] &&
  (( 10#$TF_VAR_ssh_port >= 1 && 10#$TF_VAR_ssh_port <= 65535 ))
[[ $TF_VAR_host_root =~ ^/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$ ]]

ssh_options=(-o BatchMode=yes -o StrictHostKeyChecking=yes
  -o "UserKnownHostsFile=$TF_VAR_ssh_known_hosts_file"
  -o GlobalKnownHostsFile=/dev/null -o ConnectTimeout=30
  -p "$TF_VAR_ssh_port")
destination="$TF_VAR_ssh_user@$TF_VAR_ssh_host"
ssh "${ssh_options[@]}" "$destination" \
  "sudo -n bash -s -- '$TF_VAR_ssh_user'" < "$script_dir/install-docker.sh"
ssh "${ssh_options[@]}" "$destination" \
  "sudo -n bash -s -- '$TF_VAR_host_root'" < "$script_dir/prepare-host.sh"
# A new login is needed to pick up the deploy user's Docker group membership.
ssh "${ssh_options[@]}" "$destination" 'docker info >/dev/null'
