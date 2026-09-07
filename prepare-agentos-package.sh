#!/usr/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository=$script_dir/archiso/agentos-repo
image_package_dir=$script_dir/archiso/airootfs/opt/agentos

[[ -n ${AGENTOS_PACKAGE:-} ]] || {
  printf 'error: set AGENTOS_PACKAGE to a prebuilt full-host agentos Arch package\n' >&2
  exit 1
}
package=$(realpath -- "$AGENTOS_PACKAGE")
[[ -n $package && -f $package ]]

mkdir -p -- "$repository" "$image_package_dir"
find "$repository" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -delete
install -m 0644 -- "$package" "$repository/"
repo-add "$repository/agentos-local.db.tar.gz" "$repository/${package##*/}"
install -m 0644 -- "$package" "$image_package_dir/agentos.pkg.tar.zst"
