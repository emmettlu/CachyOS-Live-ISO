#!/usr/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source_dir=${CALCULET_PCIE_SOURCE_DIR:-${1:-}}

if [[ -z ${source_dir} ]]; then
  printf 'set CALCULET_PCIE_SOURCE_DIR or pass the cal-pcie source directory\n' >&2
  exit 2
fi

source_dir=$(realpath -- "${source_dir}")
if [[ -f ${source_dir}/driver/Makefile ]]; then
  source_dir=${source_dir}/driver
fi

if [[ ! -f ${source_dir}/Makefile ]] || \
    ! grep -Eq '^[[:space:]]*obj-m[[:space:]]*[:+]?=[[:space:]]*calculet_pci[.]o' \
      "${source_dir}/Makefile"; then
  printf 'CALCULET driver Makefile does not build calculet_pci.ko: %s\n' \
    "${source_dir}/Makefile" >&2
  exit 1
fi

read_define() {
  local name=$1
  awk -v name="${name}" \
    '$1 == "#define" && $2 == name { print $3; exit }' \
    "${source_dir}/ioctl.h"
}

if [[ -n ${CALCULET_PCIE_VERSION:-} ]]; then
  pkgver=${CALCULET_PCIE_VERSION}
else
  if [[ ! -f ${source_dir}/ioctl.h ]]; then
    printf 'set CALCULET_PCIE_VERSION because ioctl.h is missing\n' >&2
    exit 1
  fi
  major=$(read_define CALCULET_DRV_VER_MAJOR)
  minor=$(read_define CALCULET_DRV_VER_MINOR)
  revision=$(read_define CALCULET_DRV_VER_REVISION)
  if [[ ! ${major} =~ ^[0-9]+$ || ! ${minor} =~ ^[0-9]+$ || \
        ! ${revision} =~ ^[0-9]+$ ]]; then
    printf 'unable to derive driver version from %s\n' \
      "${source_dir}/ioctl.h" >&2
    exit 1
  fi
  pkgver=${major}.${minor}.${revision}
fi
if [[ ! ${pkgver} =~ ^[0-9]+([.][0-9A-Za-z_+]+)*$ ]]; then
  printf 'invalid CALCULET PCIe package version: %s\n' "${pkgver}" >&2
  exit 2
fi

stage_root=$(mktemp -d -p /tmp calculet-pcie-package.XXXXXX)
trap 'find "${stage_root}" -depth -delete' EXIT
stage_source=${stage_root}/calculet-pci-${pkgver}
mkdir -p -- "${stage_source}"

rsync -a \
  --exclude '/.git/' \
  --exclude '/build/' \
  --exclude '/package/' \
  --exclude '/pkg/' \
  --exclude '*.ko' \
  --exclude '*.o' \
  --exclude '*.o.cmd' \
  --exclude '*.mod' \
  --exclude '*.mod.c' \
  --exclude '*.symvers' \
  --exclude 'modules.order' \
  "${source_dir}/" "${stage_source}/"

sed "s/@PKGVER@/${pkgver}/g" "${script_dir}/PKGBUILD.in" \
  > "${stage_root}/PKGBUILD"
sed "s/@PKGVER@/${pkgver}/g" "${script_dir}/dkms.conf.in" \
  > "${stage_root}/dkms.conf"
bsdtar -caf "${stage_root}/calculet-pci-${pkgver}.tar.zst" \
  -C "${stage_root}" "calculet-pci-${pkgver}"

(
  cd -- "${stage_root}"
  makepkg --cleanbuild --clean --force --noconfirm --nodeps
)

package=$(find "${stage_root}" -maxdepth 1 -type f \
  -name 'calculet-pcie-dkms-*.pkg.tar.*' -printf '%T@ %p\n' \
  | sort -nr | sed -n '1s/^[^ ]* //p')
if [[ -z ${package} || ! -f ${package} ]]; then
  printf 'calculet-pcie-dkms package was not produced\n' >&2
  exit 1
fi

find "${script_dir}" -maxdepth 1 -type f \
  -name 'calculet-pcie-dkms-*.pkg.tar.*' -delete
install -m 0644 -- "${package}" "${script_dir}/${package##*/}"
printf '%s\n' "${script_dir}/${package##*/}"
