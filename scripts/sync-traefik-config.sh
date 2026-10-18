#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "Traefik configuration sync failed at line %s\n" "$LINENO" >&2' ERR

if [[ $# != 2 || ! -d $1 || $2 != /* || $2 == / ]]; then
  echo "Usage: sync-traefik-config.sh SOURCE_DIRECTORY ABSOLUTE_TARGET_DIRECTORY" >&2
  exit 1
fi

source_dir=$(cd -- "$1" && pwd -P)
target_dir=$2
install -d -m 0755 -- "$target_dir"
target_dir=$(cd -- "$target_dir" && pwd -P)
if [[ $source_dir == "$target_dir" || $target_dir == / ]]; then
  echo "Source and target must be distinct non-root directories" >&2
  exit 1
fi

shopt -s nullglob
files=("$source_dir"/*.yml "$source_dir"/*.yaml)
for file in "${files[@]}"; do
  name=${file##*/}
  if [[ ! -f $file || -L $file || ! $name =~ ^[A-Za-z0-9][A-Za-z0-9_-]*\.ya?ml$ ]]; then
    printf "Invalid Traefik configuration file: %s\n" "$file" >&2
    exit 1
  fi
done

for file in "${files[@]}"; do
  name=${file##*/}
  if [[ -f $target_dir/$name ]] && cmp -s -- "$file" "$target_dir/$name"; then
    continue
  fi
  install -m 0644 -- "$file" "$target_dir/.$name.tmp"
  mv -f -- "$target_dir/.$name.tmp" "$target_dir/$name"
done

# Preserve the mounted directory inode so Traefik keeps watching it.
for file in "$target_dir"/*.yml "$target_dir"/*.yaml; do
  if [[ ! -f $source_dir/${file##*/} ]]; then
    rm -- "$file"
  fi
done
