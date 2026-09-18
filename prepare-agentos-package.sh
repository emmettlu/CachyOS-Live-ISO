#!/usr/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository=$script_dir/archiso/agentos-repo
image_package_dir=$script_dir/archiso/airootfs/opt/agentos

: "${AGENTOS_PACKAGES_DIR:?set AGENTOS_PACKAGES_DIR to the five prebuilt Arch packages}"
input=$(realpath -- "$AGENTOS_PACKAGES_DIR")
[[ -d $input ]] || exit 1
packages=(agentos-utils agentos-runtime calculet-npu-utils calculet-npu-dkms calculet-npu-firmware)
declare -A selected=()
release=
shopt -s nullglob
for archive in "$input"/*.pkg.tar.zst; do
    [[ -f $archive && ! -L $archive ]] || exit 1
    metadata=$(bsdtar -xOf "$archive" .PKGINFO)
    name=$(awk -F ' = ' '$1 == "pkgname" {print $2}' <<<"$metadata")
    case "$name" in
        agentos-utils|agentos-runtime|calculet-npu-utils|calculet-npu-dkms|calculet-npu-firmware) ;;
        *) continue ;;
    esac
    [[ ! -v selected[$name] ]] || { printf 'duplicate package: %s\n' "$name" >&2; exit 1; }
    version=$(awk -F ' = ' '$1 == "pkgver" {print $2}' <<<"$metadata")
    architecture=$(awk -F ' = ' '$1 == "arch" {print $2}' <<<"$metadata")
    [[ $architecture == x86_64 || $architecture == any ]] || { echo 'unsupported package architecture' >&2; exit 1; }
    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]] || exit 1
    [[ -z $release || $release == "${version%-*}" ]] || { echo 'package versions differ' >&2; exit 1; }
    release=${version%-*}
    selected[$name]=$archive
done
for name in "${packages[@]}"; do
    [[ -v selected[$name] ]] || { printf 'missing package: %s\n' "$name" >&2; exit 1; }
done
# Validate every input before replacing any published package or database.
stage=$(mktemp -d "$script_dir/archiso/.agentos-packages.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/repository" "$stage/image"
for name in "${packages[@]}"; do
    install -m0644 -- "${selected[$name]}" "$stage/repository/"
    install -m0644 -- "${selected[$name]}" "$stage/image/$name.pkg.tar.zst"
done
(cd "$stage/image" && sha256sum -- *.pkg.tar.zst > SHA256SUMS)
repo-add "$stage/repository/agentos-local.db.tar.gz" "$stage/repository/"*.pkg.tar.zst
[[ ! -L $repository && ! -L $image_package_dir ]] || exit 1
mkdir -p -- "$repository" "$image_package_dir"
cp -a -- "$stage/repository/." "$repository/"
cp -a -- "$stage/image/." "$image_package_dir/"
