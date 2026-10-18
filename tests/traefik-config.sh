#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "Traefik config test failed at line %s\n" "$LINENO" >&2' ERR

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/source" "$work/target"
source_dir=$work/source
target_dir=$work/target
sync_script=$repo/scripts/sync-traefik-config.sh

printf 'tcp: {}\n' > "$source_dir/mysql.yml"
bash "$sync_script" "$source_dir" "$target_dir"
cmp "$source_dir/mysql.yml" "$target_dir/mysql.yml"
directory_inode=$(stat -c '%i' "$target_dir")
file_inode=$(stat -c '%i' "$target_dir/mysql.yml")

bash "$sync_script" "$source_dir" "$target_dir"
[[ $(stat -c '%i' "$target_dir/mysql.yml") == "$file_inode" ]]

printf 'tcp:\n  routers: {}\n' > "$source_dir/mysql.yml"
printf 'http: {}\n' > "$source_dir/service.yaml"
bash "$sync_script" "$source_dir" "$target_dir"
cmp "$source_dir/mysql.yml" "$target_dir/mysql.yml"
cmp "$source_dir/service.yaml" "$target_dir/service.yaml"
[[ $(stat -c '%i' "$target_dir") == "$directory_inode" ]]
[[ $(stat -c '%i' "$target_dir/mysql.yml") != "$file_inode" ]]
[[ ! -e $target_dir/.mysql.yml.tmp ]]

printf 'unmanaged\n' > "$target_dir/keep.txt"
rm -- "$source_dir/mysql.yml"
bash "$sync_script" "$source_dir" "$target_dir"
[[ ! -e $target_dir/mysql.yml && -f $target_dir/service.yaml && -f $target_dir/keep.txt ]]

rm -- "$source_dir/service.yaml"
bash "$sync_script" "$source_dir" "$target_dir"
[[ ! -e $target_dir/service.yaml && -f $target_dir/keep.txt ]]
[[ $(stat -c '%i' "$target_dir") == "$directory_inode" ]]

printf 'tcp: {}\n' > "$source_dir/bad name.yml"
if bash "$sync_script" "$source_dir" "$target_dir" > "$work/error" 2>&1; then
  echo "Invalid filenames must fail" >&2
  exit 1
fi
grep -q "Invalid Traefik configuration file" "$work/error"

if bash "$sync_script" "$source_dir" "$source_dir" > "$work/error" 2>&1; then
  echo "Source and target must not be the same" >&2
  exit 1
fi
grep -q "Source and target must be distinct" "$work/error"

if bash "$sync_script" "$work/missing" "$target_dir" > "$work/error" 2>&1; then
  echo "A missing source must fail without deleting deployed files" >&2
  exit 1
fi
[[ -f $target_dir/keep.txt ]]
echo "Traefik config synchronization tests passed"
