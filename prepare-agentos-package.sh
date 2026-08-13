#!/usr/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if [[ -n ${AGENTOS_SOURCE_DIR:-} ]]; then
  agentos_source=$AGENTOS_SOURCE_DIR
elif [[ -d $script_dir/../packaging/arch ]]; then
  agentos_source=$script_dir/..
elif [[ -d $script_dir/../emmett/packaging/arch ]]; then
  agentos_source=$script_dir/../emmett
else
  agentos_source=$script_dir/../agentos/emmett
fi
agentos_source=$(cd -- "$agentos_source" && pwd -P)
package_dir=$agentos_source/packaging/arch
repository=$script_dir/archiso/agentos-repo
image_package_dir=$script_dir/archiso/airootfs/opt/agentos

if [[ -n ${AGENTOS_PACKAGE:-} ]]; then
  package=$(realpath -- "$AGENTOS_PACKAGE")
else
  "$package_dir/build-package.sh" --nocheck
  package=$(find "$package_dir" -maxdepth 1 -type f \
    -name 'agentos-*.pkg.tar.zst' -printf '%T@ %p\n' | sort -nr | sed -n '1s/^[^ ]* //p')
fi
[[ -n $package && -f $package ]]

mkdir -p -- "$repository" "$image_package_dir"
find "$repository" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -delete
install -m 0644 -- "$package" "$repository/"
repo-add "$repository/agentos-local.db.tar.gz" "$repository/${package##*/}"
install -m 0644 -- "$package" "$image_package_dir/agentos.pkg.tar.zst"
