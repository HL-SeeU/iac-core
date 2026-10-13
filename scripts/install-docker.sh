#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Docker installation failed at line $LINENO" >&2' ERR

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
deploy_user=${1:?Usage: install-docker.sh DEPLOY_USER}
id "$deploy_user" >/dev/null

if ! command -v docker >/dev/null 2>&1; then
  . /etc/os-release
  case "$ID" in
    ubuntu|debian) ;;
    *) echo "Only Ubuntu and Debian are supported, got: $ID" >&2; exit 1 ;;
  esac
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl --fail --silent --show-error --location "https://download.docker.com/linux/$ID/gpg" \
    -o /etc/apt/keyrings/docker.asc
  chmod 0644 /etc/apt/keyrings/docker.asc
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
    "$(dpkg --print-architecture)" "$ID" "$VERSION_CODENAME" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
fi

systemctl enable --now docker
getent group docker >/dev/null || groupadd docker
usermod -aG docker "$deploy_user"
docker info >/dev/null
