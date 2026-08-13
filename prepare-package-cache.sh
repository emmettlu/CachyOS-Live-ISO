#!/usr/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
profile=${1:-desktop}
build_profile=${2:-${script_dir}/archiso}
cache_root=${AGENTOS_ISO_CACHE_DIR:-${script_dir}/.build-cache/pacman}
ttl_hours=${AGENTOS_ISO_CACHE_TTL_HOURS:-48}
force_refresh=${AGENTOS_ISO_REFRESH_CACHE:-false}

cache_root=$(realpath -m -- "${cache_root}")
if [[ ${cache_root} == / ]]; then
    printf 'AGENTOS_ISO_CACHE_DIR must not be the filesystem root\n' >&2
    exit 2
fi

package_list=${script_dir}/archiso/packages_${profile}.x86_64
source_config=${script_dir}/archiso/pacman.conf
local_repository=${script_dir}/archiso/agentos-repo
cache_db=${cache_root}/db
cache_packages=${cache_root}/packages
cache_manifest=${cache_root}/manifest
cache_inputs=${cache_root}/inputs.sha256
cache_timestamp=${cache_root}/refreshed-at
upstream_config=${cache_root}/upstream.conf
snapshot_database=${cache_packages}/agentos-snapshot.db.tar.gz
snapshot_database_link=${cache_packages}/agentos-snapshot.db

if [[ ! ${ttl_hours} =~ ^[0-9]+$ ]] || ((ttl_hours < 1)); then
    printf 'AGENTOS_ISO_CACHE_TTL_HOURS must be a positive integer\n' >&2
    exit 2
fi

for path in "${package_list}" "${source_config}" "${local_repository}/agentos-local.db.tar.gz"; do
    if [[ ! -f ${path} ]]; then
        printf 'required package-cache input is missing: %s\n' "${path}" >&2
        exit 1
    fi
done

mapfile -t build_packages < <(
    sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "${package_list}"
)
mapfile -d '' -t local_packages < <(
    find "${local_repository}" -maxdepth 1 -type f \
        -name '*.pkg.tar.*' ! -name '*.sig' -print0 | sort -z
)

if ((${#build_packages[@]} == 0 || ${#local_packages[@]} == 0)); then
    printf 'package list or AgentOS local repository is empty\n' >&2
    exit 1
fi

input_fingerprint=$(
    {
        sha256sum "${package_list}" "${source_config}"
        for package in "${local_packages[@]}"; do
            printf '%s\n' "${package##*/}"
            bsdtar -xOf "${package}" .PKGINFO \
                | grep -E '^(pkgname|pkgver|arch|depend|provides|conflict) = ' \
                || true
        done
    } | sha256sum | awk '{print $1}'
)

manifest_complete() {
    local name version url filename

    [[ -s ${cache_manifest} ]] || return 1
    while IFS='|' read -r name version url filename; do
        [[ -n ${name} && -n ${version} && -n ${url} && -n ${filename} ]] || return 1
        [[ -f ${cache_packages}/${filename} ]] || return 1
    done < "${cache_manifest}"
}

cache_complete() {
    [[ -f ${snapshot_database} && -e ${snapshot_database_link} ]] && manifest_complete
}

cache_is_fresh=false
if [[ -f ${cache_timestamp} && -f ${cache_inputs} ]]; then
    refreshed_at=$(<"${cache_timestamp}")
    cached_fingerprint=$(<"${cache_inputs}")
    current_time=$(date +%s)
    if [[ ${refreshed_at} =~ ^[0-9]+$ ]] && \
        ((current_time >= refreshed_at)) && \
        ((current_time - refreshed_at < ttl_hours * 3600)) && \
        [[ ${cached_fingerprint} == "${input_fingerprint}" ]] && \
        cache_complete; then
        cache_is_fresh=true
    fi
fi

case ${force_refresh} in
    1|true|yes) cache_is_fresh=false ;;
    0|false|no) ;;
    *)
        printf 'AGENTOS_ISO_REFRESH_CACHE must be true or false\n' >&2
        exit 2
        ;;
esac

mkdir -p -- "${cache_db}" "${cache_packages}"

write_upstream_config() {
    cp -- "${source_config}" "${upstream_config}"
    {
        printf '\n[agentos-local]\n'
        printf 'SigLevel = Optional TrustAll\n'
        printf 'Server = file://%s\n' "${local_repository}"
    } >> "${upstream_config}"
}

copy_known_packages() {
    local name version url filename source signature

    while IFS='|' read -r name version url filename; do
        source=${local_repository}/${filename}
        if [[ -f ${source} ]]; then
            cp --reflink=auto --preserve=mode,timestamps -- \
                "${source}" "${cache_packages}/${filename}"
            if [[ -f ${source}.sig ]]; then
                cp --reflink=auto --preserve=mode,timestamps -- \
                    "${source}.sig" "${cache_packages}/${filename}.sig"
            fi
            continue
        fi
        [[ -f ${cache_packages}/${filename} ]] && continue
        for source in "/var/cache/pacman/pkg/${filename}"; do
            [[ -f ${source} ]] || continue
            cp --reflink=auto --preserve=mode,timestamps -- \
                "${source}" "${cache_packages}/${filename}"
            signature=${source}.sig
            if [[ -f ${signature} ]]; then
                cp --reflink=auto --preserve=mode,timestamps -- \
                    "${signature}" "${cache_packages}/${filename}.sig"
            fi
            break
        done
    done < "${cache_manifest}"
}

manifest_package_paths() {
    local name version url filename
    snapshot_packages=()
    while IFS='|' read -r name version url filename; do
        if [[ ! -f ${cache_packages}/${filename} ]]; then
            printf 'cached package is missing: %s\n' "${filename}" >&2
            exit 1
        fi
        snapshot_packages+=("${cache_packages}/${filename}")
    done < "${cache_manifest}"
}

rebuild_snapshot_database() {
    find "${cache_packages}" -maxdepth 1 \( -type f -o -type l \) \
        \( -name 'agentos-snapshot.db*' -o -name 'agentos-snapshot.files*' \) \
        -delete
    manifest_package_paths
    repo-add "${snapshot_database}" "${snapshot_packages[@]}" >/dev/null
}

if [[ ${cache_is_fresh} == false ]]; then
    printf 'Refreshing frozen package cache (TTL: %s hours)\n' "${ttl_hours}"
    write_upstream_config
    sudo pacman -Syy --noconfirm \
        --dbpath "${cache_db}" \
        --cachedir "${cache_packages}" \
        --config "${upstream_config}"

    resolution_file=$(mktemp "${cache_root}/resolution.XXXXXX")
    manifest_file=$(mktemp "${cache_root}/manifest.XXXXXX")
    sudo pacman -Sp --noconfirm --print-format '%n|%v|%l' \
        --dbpath "${cache_db}" \
        --cachedir "${cache_packages}" \
        --config "${upstream_config}" \
        "${build_packages[@]}" > "${resolution_file}"

    while IFS='|' read -r name version url; do
        filename=${url##*/}
        filename=${filename%%\?*}
        if [[ -z ${name} || -z ${version} || -z ${url} || -z ${filename} ]]; then
            printf 'invalid package resolution entry: %s|%s|%s\n' \
                "${name}" "${version}" "${url}" >&2
            exit 1
        fi
        printf '%s|%s|%s|%s\n' "${name}" "${version}" "${url}" "${filename}"
    done < "${resolution_file}" > "${manifest_file}"
    sort -u -o "${manifest_file}" "${manifest_file}"
    mv -f -- "${manifest_file}" "${cache_manifest}"
    rm -f -- "${resolution_file}"

    copy_known_packages
    sudo pacman -Sw --noconfirm \
        --dbpath "${cache_db}" \
        --cachedir "${cache_packages}" \
        --config "${upstream_config}" \
        "${build_packages[@]}"
    sudo chown -R "$(id -u):$(id -g)" "${cache_db}" "${cache_packages}"

    manifest_complete || {
        printf 'package cache refresh did not produce a complete snapshot\n' >&2
        exit 1
    }
    rebuild_snapshot_database
    printf '%s\n' "${input_fingerprint}" > "${cache_inputs}"
    date +%s > "${cache_timestamp}"
else
    refreshed_at=$(<"${cache_timestamp}")
    cache_age_hours=$((($(date +%s) - refreshed_at) / 3600))
    printf 'Reusing frozen package cache (%s hours old)\n' "${cache_age_hours}"

    cached_local_packages=()
    for package in "${local_packages[@]}"; do
        cached_package=${cache_packages}/${package##*/}
        install -m 0644 -- "${package}" "${cached_package}"
        if [[ -f ${package}.sig ]]; then
            install -m 0644 -- "${package}.sig" "${cached_package}.sig"
        fi
        cached_local_packages+=("${cached_package}")
    done
    repo-add "${snapshot_database}" "${cached_local_packages[@]}" >/dev/null
fi

mkdir -p -- "${build_profile}"
{
    printf '[options]\n'
    printf 'Architecture = auto\n'
    printf 'CheckSpace\n'
    printf 'ParallelDownloads = 5\n'
    printf 'CacheDir = %s\n' "${cache_packages}"
    printf 'SigLevel = Optional TrustAll\n'
    printf 'LocalFileSigLevel = Optional\n'
    printf '\n[agentos-snapshot]\n'
    printf 'SigLevel = Optional TrustAll\n'
    printf 'Server = file://%s\n' "${cache_packages}"
} > "${build_profile}/pacman.conf"
