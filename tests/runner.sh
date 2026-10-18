#!/usr/bin/env bash
set -Eeuo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$repo"
command -v jq >/dev/null || { echo "runner tests require jq" >&2; exit 1; }
work=$(umask 077; mktemp -d "$repo/.runner-tests.XXXXXX")
cleanup_tests() {
  local pid
  if [[ -f $work/agent-pids ]]; then
    while IFS= read -r pid; do kill "$pid" 2>/dev/null || :; done < "$work/agent-pids"
  fi
  if [[ -n ${unrelated_pid:-} ]]; then kill "$unrelated_pid" 2>/dev/null || :; fi
  rm -rf -- "$work"
}
trap cleanup_tests EXIT
trap 'printf "Runner test failed at line %s (last command order):\n" "$LINENO" >&2; cat "$work/order" >&2; if ! grep -q SECRET_ "$work/output"; then cat "$work/output" >&2; fi' ERR
mkdir "$work/bin"
export TEST_STATE=$work
export PATH="$work/bin:$PATH"

cat > "$work/bin/ssh-agent" <<'MOCK'
#!/usr/bin/env bash
set -eu
[[ $1 == -a && $3 == -s ]]
sleep 300 </dev/null >/dev/null 2>&1 &
pid=$!
printf '%s\n' "$pid" >> "$TEST_STATE/agent-pids"
printf '%s\n' "$2" >> "$TEST_STATE/agent-sockets"
printf 'SSH_AUTH_SOCK=%s; export SSH_AUTH_SOCK;\n' "$2"
printf 'SSH_AGENT_PID=%s; export SSH_AGENT_PID;\n' "$pid"
MOCK
cat > "$work/bin/ssh-add" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == - ]]
key=$(cat)
[[ $key == SECRET_PRIVATE_KEY ]]
[[ ${TEST_ADD_FAIL:-0} == 0 ]]
MOCK
cat > "$work/bin/ssh-keygen" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == -F && $3 == -f ]]
printf '%s\n' "$4" >> "$TEST_STATE/trust-files"
awk -v host="$2" '$1 == host {print; found=1} END {exit !found}' "$4"
MOCK
cat > "$work/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
set -eu
trap 'printf "Mock SSH check failed at line %s\n" "$LINENO" >&2' ERR
[[ $* == *BatchMode=yes* ]]
if [[ $TF_VAR_ssh_host_key_check == true ]]; then
  [[ $* == *StrictHostKeyChecking=yes* ]]
  [[ $* == *"UserKnownHostsFile=$TF_VAR_ssh_known_hosts_file"* ]]
else
  [[ $TF_VAR_ssh_host_key_check == false ]]
  [[ $* == *StrictHostKeyChecking=no* && $* == *UserKnownHostsFile=/dev/null* ]]
fi
[[ $* == *GlobalKnownHostsFile=/dev/null* ]]
[[ -n $SSH_AUTH_SOCK && -f $TF_VAR_ssh_known_hosts_file ]]
case "$(uname -s)" in
  MINGW*|MSYS*) ;; # Windows filesystems do not expose POSIX permission modes.
  *)
    [[ $(stat -c '%a' "$TF_VAR_ssh_known_hosts_file") == 600 ]]
    [[ $(stat -c '%a' "${TF_VAR_ssh_known_hosts_file%/*}") == 700 ]]
    ;;
esac
[[ $(cat "$TF_VAR_ssh_known_hosts_file") == "$TEST_TRUSTED_HOSTS" ]]
[[ $(find "${TF_VAR_ssh_known_hosts_file%/*}" -type f | wc -l) == 1 ]]
case "${!#}" in
  *sudo*install*) exit 91 ;;
  *"sudo -n bash -s -- 'deploy'"*) label=install; cat >/dev/null ;;
  *"sudo -n bash -s -- '/opt/iac-core'"*) label=prepare; cat >/dev/null ;;
  *'docker info'*) label=info ;;
  *) exit 92 ;;
esac
printf '%s\n' "$label" >> "$TEST_STATE/order"
[[ ${TEST_SSH_FAIL:-0} == 0 ]]
MOCK
cat > "$work/bin/terraform" <<'MOCK'
#!/usr/bin/env bash
set -eu
[[ $PWD == "$TEST_REPO" ]]
[[ -f $TF_VAR_ssh_known_hosts_file && -n $SSH_AUTH_SOCK ]]
if [[ $TF_VAR_ssh_host_key_check == true ]]; then
  [[ $TF_VAR_ssh_host_key == "ssh-ed25519 TRUSTED_KEY" ]]
else
  [[ $TF_VAR_ssh_host_key_check == false && -z $TF_VAR_ssh_host_key ]]
fi
[[ $TF_VAR_postgres_password == SECRET_POSTGRES ]]
[[ -z ${VM_SSH_PRIVATE_KEY:-} && -z ${SSH_KNOWN_HOSTS:-} ]]
case "$1" in
  init)
    [[ $* == "init -input=false -lockfile=readonly" ]]
    echo init >> "$TEST_STATE/order"
    [[ ${TEST_INIT_FAIL:-0} == 0 ]]
    ;;
  apply|plan)
    printf '%s\n' "$1" >> "$TEST_STATE/order"
    [[ ${TEST_TF_FAIL:-0} == 0 ]]
    ;;
  *) exit 93 ;;
esac
MOCK
chmod +x "$work/bin/"*
export TEST_REPO=$repo

defaults() {
  export TF_CLOUD_ORGANIZATION=test-org TF_WORKSPACE=test-workspace
  export TF_TOKEN_app_terraform_io=SECRET_CLOUD_TOKEN
  export TF_VAR_ssh_host=example.test TF_VAR_ssh_user=deploy TF_VAR_ssh_port=22
  export TF_VAR_acme_email=ops@example.test TF_VAR_postgres_password=SECRET_POSTGRES
  export VM_SSH_PRIVATE_KEY=SECRET_PRIVATE_KEY
  export SSH_KNOWN_HOSTS='example.test ssh-ed25519 TRUSTED_KEY'
  export TEST_TRUSTED_HOSTS=$SSH_KNOWN_HOSTS
  unset TF_VAR_apps TF_VAR_app_infisical_tokens TF_VAR_host_root TF_VAR_ssh_host_key
  unset TF_VAR_ssh_host_key_check TF_VAR_cloudflare_dns_enabled CLOUDFLARE_API_TOKEN
  unset TEST_SSH_FAIL TEST_INIT_FAIL TEST_ADD_FAIL TEST_TF_FAIL
  : > "$work/order"
}

assert_cleanup() {
  local pid socket
  if [[ -f $work/agent-pids ]]; then
    while IFS= read -r pid; do
      if kill -0 "$pid" 2>/dev/null; then
        sleep 0.1
        ! kill -0 "$pid" 2>/dev/null || { echo "Agent leaked" >&2; exit 1; }
      fi
      if [[ -f $work/trust-files ]]; then
        while IFS= read -r socket; do
          [[ ! -e ${socket%/*} ]] || { echo "Trust directory leaked" >&2; exit 1; }
        done < "$work/trust-files"
      fi
      kill -0 "$unrelated_pid" 2>/dev/null || { echo "Unrelated agent process killed" >&2; exit 1; }
    done < "$work/agent-pids"
    while IFS= read -r socket; do
      [[ ! -e ${socket%/*} ]] || { echo "Runner directory leaked" >&2; exit 1; }
    done < "$work/agent-sockets"
  fi
  ! grep -q 'SECRET_' "$work/output" || { echo "Secret leaked to output" >&2; exit 1; }
}

expect_failure() {
  if bash scripts/terraform.sh apply -auto-approve > "$work/output" 2>&1; then
    echo "Expected failure: $1" >&2; exit 1
  fi
  assert_cleanup
  echo "ok: $1"
}

defaults
sleep 300 </dev/null >/dev/null 2>&1 &
unrelated_pid=$!
export SSH_AGENT_PID=$unrelated_pid SSH_AUTH_SOCK=unrelated-agent-socket
bash -c 'source scripts/runner-env.sh; cleanup_runner; [[ -z ${_runner_dir:-} && -z ${_runner_agent_pid:-} && $SSH_AUTH_SOCK == unrelated-agent-socket ]]' > "$work/output"
[[ ! -s $work/output && ! -e $work/agent-pids ]]
echo "ok: sourcing has no side effects"

defaults; unset TF_VAR_postgres_password
expect_failure "missing configuration"
[[ ! -s $work/order ]]
defaults; export TF_VAR_ssh_host_key_check=invalid
expect_failure "invalid host checking flag"
[[ ! -s $work/order ]]
defaults; export TF_VAR_cloudflare_dns_enabled=invalid
expect_failure "invalid Cloudflare DNS enabled flag"
[[ ! -s $work/order ]]
defaults; export TF_VAR_cloudflare_dns_enabled=true
expect_failure "Cloudflare token required when DNS is enabled"
[[ ! -s $work/order ]]
defaults; unset SSH_KNOWN_HOSTS
expect_failure "trusted hosts required by default"
[[ ! -s $work/order ]]
defaults; TF_CLOUD_ORGANIZATION=$'org\ninjected'
expect_failure "multiline cloud configuration"
defaults; TF_VAR_ssh_port=65536
expect_failure "invalid port"
defaults; TF_VAR_ssh_host='host;injected'
expect_failure "invalid host"
defaults; TF_VAR_ssh_user='deploy;injected'
expect_failure "invalid user"
defaults; export TF_VAR_host_root='/opt/../root'
expect_failure "invalid host directory"
defaults; export TF_VAR_apps='{invalid SECRET_JSON'
expect_failure "invalid JSON"
defaults; export TF_VAR_apps='{"api":{"user":"1000:1000"}}'
expect_failure "missing app token"
defaults; export TF_VAR_apps='{"api":{"user":"root"}}'
export TF_VAR_app_infisical_tokens='{"api":"SECRET_APP_TOKEN"}'
expect_failure "non-numeric app user"
defaults; export TF_VAR_app_infisical_tokens='{"api":42}'
expect_failure "invalid token map"
defaults; export TF_VAR_apps='[]'
expect_failure "apps must be an object"
defaults; export TF_VAR_app_infisical_tokens='[]'
expect_failure "tokens must be an object"
defaults; export TF_VAR_apps='{"api":{"user":"1000:1000"}}'
export TF_VAR_app_infisical_tokens='{"api":"  "}'
expect_failure "empty app token"
defaults; export TF_VAR_ssh_host_key='ssh-ed25519 WRONG_KEY'
expect_failure "host key mismatch"
[[ ! -s $work/order ]]
defaults; SSH_KNOWN_HOSTS='other.test ssh-ed25519 TRUSTED_KEY'
expect_failure "missing trusted host"
defaults; export TEST_ADD_FAIL=1
expect_failure "key loading failure"
defaults; export TEST_SSH_FAIL=1
expect_failure "SSH preflight failure"
[[ $(cat "$work/order") == install ]]
defaults; export TEST_INIT_FAIL=1
expect_failure "Terraform init failure"
[[ $(cat "$work/order") == $'install\nprepare\ninfo\ninit' ]]
defaults; export TEST_TF_FAIL=1
expect_failure "Terraform apply failure"
[[ $(cat "$work/order") == $'install\nprepare\ninfo\ninit\napply' ]]

defaults
export TF_VAR_apps='{"api":{"user":"1000:1000"}}'
export TF_VAR_app_infisical_tokens='{"api":"SECRET_APP_TOKEN"}'
bash scripts/terraform.sh apply -auto-approve -lock-timeout=5m > "$work/output" 2>&1
[[ $(cat "$work/order") == $'install\nprepare\ninfo\ninit\napply' ]]
assert_cleanup
echo "ok: preflight, init, single apply, credentials, and cleanup"
defaults
TF_VAR_ssh_port=00222
SSH_KNOWN_HOSTS='[example.test]:222 ssh-ed25519 TRUSTED_KEY'
TEST_TRUSTED_HOSTS=$SSH_KNOWN_HOSTS
bash scripts/terraform.sh plan > "$work/output" 2>&1
[[ $(cat "$work/order") == $'install\nprepare\ninfo\ninit\nplan' ]]
assert_cleanup
echo "ok: nondefault port and plan preflight"
defaults
bash scripts/terraform.sh > "$work/output" 2>&1
[[ $(cat "$work/order") == $'install\nprepare\ninfo\ninit\napply' ]]
assert_cleanup
echo "ok: default apply"
defaults
export TF_VAR_ssh_host_key_check=false TF_VAR_ssh_host_key='ssh-ed25519 WRONG_KEY'
SSH_KNOWN_HOSTS='other.test ssh-ed25519 WRONG_KEY'
TEST_TRUSTED_HOSTS=$SSH_KNOWN_HOSTS
bash scripts/terraform.sh apply -auto-approve > "$work/output" 2>&1
[[ $(cat "$work/order") == $'install\nprepare\ninfo\ninit\napply' ]]
grep -q 'SSH host checking is DISABLED' "$work/output"
assert_cleanup
echo "ok: diagnostic bypass ignores mismatched host keys and warns"
defaults
export TF_VAR_ssh_host_key_check=false
unset SSH_KNOWN_HOSTS
TEST_TRUSTED_HOSTS=""
bash scripts/terraform.sh plan > "$work/output" 2>&1
[[ $(cat "$work/order") == $'install\nprepare\ninfo\ninit\nplan' ]]
assert_cleanup
echo "ok: diagnostic bypass does not require known_hosts"
defaults; export TF_VAR_ssh_host_key_check=false TEST_ADD_FAIL=1
expect_failure "diagnostic bypass still requires deployment key loading"
[[ ! -s $work/order ]]
defaults; export TF_VAR_ssh_host_key_check=false TEST_SSH_FAIL=1
expect_failure "diagnostic bypass still fails on SSH errors"
[[ $(cat "$work/order") == install ]]
echo "Runner regression tests passed."
