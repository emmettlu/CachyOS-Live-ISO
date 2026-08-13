#!/usr/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository=${script_dir}/archiso/agentos-repo

if [[ -n ${AGENTOS_HELLO_PACKAGE:-} ]]; then
  package=$(realpath -- "${AGENTOS_HELLO_PACKAGE}")
else
  if [[ -n ${AGENTOS_HELLO_SOURCE_DIR:-} ]]; then
    hello_source=${AGENTOS_HELLO_SOURCE_DIR}
  elif [[ -d ${script_dir}/../CachyOS-Welcome/packaging/arch ]]; then
    hello_source=${script_dir}/../CachyOS-Welcome
  elif [[ -d ${script_dir}/CachyOS-Welcome/packaging/arch ]]; then
    hello_source=${script_dir}/CachyOS-Welcome
  else
    printf 'AgentOS Hello source not found; set AGENTOS_HELLO_SOURCE_DIR\n' >&2
    exit 1
  fi

  hello_source=$(cd -- "${hello_source}" && pwd -P)
  package_dir=${hello_source}/packaging/arch
  "${package_dir}/build-package.sh" --nocheck
  package=$(find "${package_dir}" -maxdepth 1 -type f \
    -name 'agentos-hello-*.pkg.tar.zst' -printf '%T@ %p\n' \
    | sort -nr | sed -n '1s/^[^ ]* //p')
fi

[[ -n ${package} && -f ${package} ]]
mkdir -p -- "${repository}"
find "${repository}" -maxdepth 1 -type f \
  -name 'agentos-hello-*.pkg.tar.zst' -delete
install -m 0644 -- "${package}" "${repository}/"
repo-add "${repository}/agentos-local.db.tar.gz" \
  "${repository}/${package##*/}"
