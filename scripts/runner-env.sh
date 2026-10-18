#!/usr/bin/env bash

runner_error() {
  printf 'Runner: %s\n' "$1" >&2
  return 1
}

cleanup_runner() {
  set +x
  if [[ -n ${_runner_agent_pid:-} ]]; then
    kill "$_runner_agent_pid" 2>/dev/null || :
    unset _runner_agent_pid SSH_AGENT_PID SSH_AUTH_SOCK
  fi
  if [[ -n ${_runner_dir:-} ]]; then
    rm -rf -- "$_runner_dir"
    unset _runner_dir TF_VAR_ssh_known_hosts_file
  fi
}

prepare_runner() {
  set +x
  local name value repo agent_output line
  [[ -z ${_runner_dir:-} ]] || { runner_error "Already prepared."; return 1; }
  export TF_VAR_ssh_host_key_check=${TF_VAR_ssh_host_key_check:-true}
  [[ $TF_VAR_ssh_host_key_check == true || $TF_VAR_ssh_host_key_check == false ]] || {
    runner_error "TF_VAR_ssh_host_key_check must be true or false."; return 1;
  }
  export TF_VAR_cloudflare_dns_enabled=${TF_VAR_cloudflare_dns_enabled:-false}
  [[ $TF_VAR_cloudflare_dns_enabled == true || $TF_VAR_cloudflare_dns_enabled == false ]] || {
    runner_error "TF_VAR_cloudflare_dns_enabled must be true or false."; return 1;
  }
  if [[ $TF_VAR_cloudflare_dns_enabled == true ]]; then
    value=${CLOUDFLARE_API_TOKEN:-}
    [[ -n ${value//[[:space:]]/} ]] || {
      runner_error "CLOUDFLARE_API_TOKEN is required when Cloudflare DNS is enabled."; return 1;
    }
    export CLOUDFLARE_API_TOKEN
  fi
  for name in TF_CLOUD_ORGANIZATION TF_WORKSPACE TF_TOKEN_app_terraform_io \
    TF_VAR_ssh_host TF_VAR_ssh_user TF_VAR_ssh_port TF_VAR_acme_email \
    TF_VAR_postgres_password VM_SSH_PRIVATE_KEY; do
    value=${!name:-}
    [[ -n ${value//[[:space:]]/} ]] || {
      runner_error "Required configuration $name is missing."; return 1;
    }
    export "$name"
  done
  if [[ $TF_VAR_ssh_host_key_check == true ]]; then
    value=${SSH_KNOWN_HOSTS:-}
    [[ -n ${value//[[:space:]]/} ]] || {
      runner_error "Required configuration SSH_KNOWN_HOSTS is missing."; return 1;
    }
  else
    printf 'Runner: WARNING: SSH host checking is DISABLED; server identity is not verified. Restore it after debugging.\n' >&2
  fi
  for name in TF_CLOUD_ORGANIZATION TF_WORKSPACE; do
    value=${!name}
    [[ $value != *$'\n'* && $value != *$'\r'* ]] || {
      runner_error "$name must be a single line."; return 1;
    }
  done
  export TF_VAR_host_root=${TF_VAR_host_root:-/opt/iac-core}
  export TF_VAR_apps=${TF_VAR_apps:-'{}'}
  export TF_VAR_app_infisical_tokens=${TF_VAR_app_infisical_tokens:-'{}'}
  [[ $TF_VAR_ssh_host =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
    runner_error "Invalid SSH host."; return 1;
  }
  [[ $TF_VAR_ssh_user =~ ^[a-z_][a-z0-9_-]*$ ]] || {
    runner_error "Invalid SSH user."; return 1;
  }
  [[ $TF_VAR_ssh_port =~ ^[0-9]{1,5}$ ]] &&
    (( 10#$TF_VAR_ssh_port >= 1 && 10#$TF_VAR_ssh_port <= 65535 )) || {
    runner_error "Invalid SSH port."; return 1;
  }
  # Canonicalize so trusted-key lookup and SSH use the same port representation.
  export TF_VAR_ssh_port=$((10#$TF_VAR_ssh_port))
  [[ $TF_VAR_host_root =~ ^/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$ ]] || {
    runner_error "Invalid host directory."; return 1;
  }
  for name in jq ssh-agent ssh-add ssh-keygen; do
    command -v "$name" >/dev/null 2>&1 || {
      runner_error "Required executable $name is missing."; return 1;
    }
  done
  if ! printf '%s\n%s\n' "$TF_VAR_apps" "$TF_VAR_app_infisical_tokens" |
    jq -e -s '
      length == 2 and
      (.[0] | type == "object") and (.[1] | type == "object") and
      (.[0] | all(.[]; type == "object" and
        (.user | type == "string" and test("^[0-9]+:[0-9]+$")))) and
      (.[1] | all(.[]; type == "string" and test("\\S"))) and
      (.[1] as $tokens | .[0] | keys |
        all(.[]; $tokens[.] | type == "string" and test("\\S")))
    ' >/dev/null 2>&1; then
    runner_error "Invalid apps/token JSON, numeric app user, or missing application token."
    return 1
  fi
  repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd) || return 1
  _runner_dir=$(umask 077; mktemp -d "$repo/.iac-runner.XXXXXX") || {
    runner_error "Cannot create isolated runner directory."; return 1;
  }
  chmod 0700 "$_runner_dir" || { cleanup_runner; return 1; }
  export TF_VAR_ssh_known_hosts_file="$_runner_dir/known_hosts"
  (umask 077; printf '%s\n' "${SSH_KNOWN_HOSTS:-}" > "$TF_VAR_ssh_known_hosts_file") || {
    cleanup_runner; return 1;
  }
  chmod 0600 "$TF_VAR_ssh_known_hosts_file" || { cleanup_runner; return 1; }
  if [[ $TF_VAR_ssh_host_key_check == true ]]; then
    prepare_runner_host_key || { cleanup_runner; return 1; }
  else
    export TF_VAR_ssh_host_key=""
  fi
  agent_output=$(ssh-agent -a "$_runner_dir/agent.sock" -s 2>/dev/null) || {
    runner_error "Cannot start isolated SSH agent."; cleanup_runner; return 1;
  }
  while IFS= read -r line; do
    if [[ $line =~ ^SSH_AUTH_SOCK=([^;]+)\; ]]; then
      export SSH_AUTH_SOCK=${BASH_REMATCH[1]}
    elif [[ $line =~ ^SSH_AGENT_PID=([0-9]+)\; ]]; then
      _runner_agent_pid=${BASH_REMATCH[1]}
      export SSH_AGENT_PID=$_runner_agent_pid
    fi
  done <<< "$agent_output"
  [[ -n ${_runner_agent_pid:-} && ${SSH_AUTH_SOCK:-} == "$_runner_dir/agent.sock" ]] || {
    runner_error "Invalid SSH agent response."; cleanup_runner; return 1;
  }
  if ! printf '%s\n' "$VM_SSH_PRIVATE_KEY" | ssh-add - >/dev/null 2>&1; then
    runner_error "Cannot load deployment SSH key."; cleanup_runner; return 1;
  fi
  unset VM_SSH_PRIVATE_KEY SSH_KNOWN_HOSTS
}

prepare_runner_host_key() {
  local lookup trusted_keys line
  lookup=$TF_VAR_ssh_host
  [[ $TF_VAR_ssh_port == 22 ]] || lookup="[$TF_VAR_ssh_host]:$TF_VAR_ssh_port"
  trusted_keys=$(ssh-keygen -F "$lookup" -f "$TF_VAR_ssh_known_hosts_file" 2>/dev/null |
    awk '!/^#/ && $1 !~ /^@/ && NF >= 3 {print $2 " " $3}') || {
    runner_error "Cannot resolve trusted SSH host key."; return 1;
  }
  [[ -n $trusted_keys ]] || {
    runner_error "No trusted SSH key for configured host and port."; return 1;
  }
  if [[ -n ${TF_VAR_ssh_host_key:-} ]]; then
    local matched=false
    while IFS= read -r line; do
      [[ $line != "$TF_VAR_ssh_host_key" ]] || matched=true
    done <<< "$trusted_keys"
    [[ $matched == true ]] || {
      runner_error "SSH host key does not match trusted known_hosts."; return 1;
    }
  else
    TF_VAR_ssh_host_key=${trusted_keys%%$'\n'*}
  fi
  export TF_VAR_ssh_host_key
}
