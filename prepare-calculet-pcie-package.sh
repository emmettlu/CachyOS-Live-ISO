#!/usr/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository=${script_dir}/archiso/agentos-repo
image_package_dir=${script_dir}/archiso/airootfs/opt/agentos

if [[ -n ${CALCULET_PCIE_PACKAGE:-} ]]; then
  package=$(realpath -- "${CALCULET_PCIE_PACKAGE}")
else
  if [[ -n ${CALCULET_PCIE_SOURCE_DIR:-} ]]; then
    driver_source=${CALCULET_PCIE_SOURCE_DIR}
  elif [[ -d ${script_dir}/../../../ks1-upstream-handoff/20-驱动与PCIe/cal-pcie/driver ]]; then
    driver_source=${script_dir}/../../../ks1-upstream-handoff/20-驱动与PCIe/cal-pcie/driver
  else
    printf 'CALCULET PCIe source not found; set CALCULET_PCIE_SOURCE_DIR\n' >&2
    exit 1
  fi

  package_dir=${script_dir}/packaging/calculet-pcie-dkms
  CALCULET_PCIE_SOURCE_DIR=${driver_source} "${package_dir}/build-package.sh"
  package=$(find "${package_dir}" -maxdepth 1 -type f \
    -name 'calculet-pcie-dkms-*.pkg.tar.*' -printf '%T@ %p\n' \
    | sort -nr | sed -n '1s/^[^ ]* //p')
fi

if [[ -z ${package} || ! -f ${package} ]]; then
  printf 'CALCULET PCIe package not found\n' >&2
  exit 1
fi
if ! bsdtar -xOf "${package}" .PKGINFO \
    | grep -Fxq 'pkgname = calculet-pcie-dkms'; then
  printf 'not a calculet-pcie-dkms package: %s\n' "${package}" >&2
  exit 1
fi

mkdir -p -- "${repository}" "${image_package_dir}"
find "${repository}" -maxdepth 1 -type f \
  -name 'calculet-pcie-dkms-*.pkg.tar.*' -delete
install -m 0644 -- "${package}" "${repository}/"
repo-add "${repository}/agentos-local.db.tar.gz" \
  "${repository}/${package##*/}"
install -m 0644 -- "${package}" \
  "${image_package_dir}/calculet-pcie-dkms.pkg.tar.zst"
