#!/usr/bin/env bash

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

validate_identifier() {
  [[ $1 =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || {
    echo "Invalid PostgreSQL identifier: $1" >&2
    exit 1
  }
}

validate_container() {
  [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
    echo "Invalid Docker container name: $1" >&2
    exit 1
  }
}
