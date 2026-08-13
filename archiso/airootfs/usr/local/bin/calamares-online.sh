#!/bin/bash

main() {
    local progname="$(basename "$0")"
    local log="/home/liveuser/agentos-install.log"
    local mode="offline"

    local SYSTEM=""

    if [ -d /sys/firmware/efi ]; then
        SYSTEM="UEFI SYSTEM"
    else
        SYSTEM="BIOS/MBR SYSTEM"
    fi

    local ISO_VERSION="$(cat /etc/version-tag)"
    echo "USING ISO VERSION: ${ISO_VERSION}"

    if ! sudo /usr/local/bin/agentos-configure-calamares; then
        printf 'AgentOS Installer configuration failed; refusing to launch Calamares\n' >&2
        exit 1
    fi

    # Get Hardware Informations
    inxi -F > "$log"

    cat <<EOF >> "$log"
########## $log by $progname
########## Started (UTC): $(date -u "+%x %X")
########## ISO version: $ISO_VERSION
########## System: $SYSTEM
EOF

    sudo cp "/usr/share/calamares/settings_${mode}.conf" /etc/calamares/settings.conf
    exec pkexec-wrapper calamares -D6 >> $log
}

main "$@"
