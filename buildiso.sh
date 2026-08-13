#!/bin/bash
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

set -e
src_dir=$(pwd)
if ((EUID == 0)); then
    printf 'run buildiso.sh as a non-root user with sudo access\n' >&2
    exit 1
fi
[[ -r ${src_dir}/util-msg.sh ]] && source ${src_dir}/util-msg.sh
import ${src_dir}/util.sh

# setting of the general parameters
work_dir="${src_dir}/build"
outFolder="${src_dir}/out"

build_list_iso="desktop"
clean_first=true
verbose=false
build_in_ram=false
remove_build_dir=false
package_cache_ttl_hours=${AGENTOS_ISO_CACHE_TTL_HOURS:-48}
refresh_package_cache=false

usage() {
    echo "Usage: ${0##*/} [options]"
    echo '    -c                 Disable clean work dir'
    echo '    -r                 Enable building in RAM on systems with more than 23GB RAM'
    echo '    -w                 Remove build directory (not the ISO) after ISO file is built'
    echo '    -F                 Force refresh of the frozen package cache'
    echo "    -t <hours>         Package cache lifetime [default: ${package_cache_ttl_hours}]"
    echo "    -p <profile>       Buildset or profile [default: ${build_list_iso}]"
    echo '    -v                 Verbose output to log file, show profile detail (-q)'
    echo '    -h                 This help'
    echo ''
    echo ''
    exit $1
}

orig_argv=("$@")

opts='p:cvhrwFt:'

while getopts "${opts}" arg; do
    case "${arg}" in
        c) clean_first=false ;;
        p) build_list_iso="$OPTARG" ;;
        r) build_in_ram=true ;;
        w) remove_build_dir=true ;;
        F) refresh_package_cache=true ;;
        t) package_cache_ttl_hours="$OPTARG" ;;
        v) verbose=true ;;
        h|?) usage 0 ;;
        *) echo "invalid argument '${arg}'"; usage 1 ;;
    esac
done

shift $(($OPTIND - 1))

if [[ ! ${package_cache_ttl_hours} =~ ^[0-9]+$ ]] || \
    ((package_cache_ttl_hours < 1)); then
    printf 'package cache lifetime must be a positive integer\n' >&2
    exit 2
fi

export AGENTOS_ISO_CACHE_TTL_HOURS=${package_cache_ttl_hours}
export AGENTOS_ISO_REFRESH_CACHE=${refresh_package_cache}

timer_start=$(get_timer)

"${src_dir}/prepare-agentos-package.sh"
"${src_dir}/prepare-agentos-hello-package.sh"

#check_root "$0" "${orig_argv[@]}"

# Build ISO in RAM if RAM amount is greater than 23GB. This would speed up build process and extend disk lifetime 
if [[ "$build_in_ram" == "true" ]] && [[ $(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}') -gt 23 ]]; then
    work_dir="$(mktemp -d --suffix="-cachyos-iso")"
fi

prepare_dir "${work_dir}"

import ${src_dir}/util-iso.sh
import ${src_dir}/util-iso-mount.sh

check_requirements

for sig in TERM HUP QUIT; do
    trap "trap_exit $sig \"$(gettext "%s signal caught. Exiting...")\" \"$sig\"" "$sig"
done
trap 'trap_exit INT "$(gettext "Aborted by user! Exiting...")"' INT
trap 'trap_exit USR1 "$(gettext "An unknown error has occurred. Exiting...")"' ERR
trap 'trap_exit EXIT "$(gettext "An unknown error has occurred. Exiting...")"' EXIT

run_build "${build_list_iso}"
