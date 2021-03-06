#!/bin/bash


function update_nspawn_container { ## container
    
    local C
    C="$1"
    source /etc/os-release
    
    run ssh "$C" "dnf -y install kernel kernel-modules kernel-core kernel-headers dnf-plugin-system-upgrade"
    run ssh "$C" "dnf -y upgrade --refresh"
    run ssh "$C" "dnf -y system-upgrade download --refresh --releasever=$VERSION_ID"
    #exif
    run ssh "$C" "dnf -y system-upgrade reboot"
    sleep 3
    run systemctl status srvctl-nspawn@"$C" --no-pager
    run systemctl is-active srvctl-nspawn@"$C"
    sleep 3
    if [[ "$(systemctl is-active srvctl-nspawn@"$C")" != active ]]
    then
        ntc "$C inactive"
        run systemctl stop srvctl-nspawn@"$C" --no-pager
        sleep 1
        run /usr/bin/systemd-nspawn --boot --settings=trusted --machine="$C" -D /srv/"$C"/rootfs
        msg "Starting container"
        sleep 1
        run systemctl start srvctl-nspawn@"$C"
        sleep 3
        run systemctl status srvctl-nspawn@"$C" --no-pager
    fi
    msg "Ready"
}
