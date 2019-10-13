#!/bin/bash

function create_nspawn_container_settings { ## container
    
    local C
    C="$1"
    
    msg "Create nspawn container settings for $C)"
    
    mkdir -p "/var/srvctl3/share/containers/$C/users"
    
    ## create the nspawn file
    cfg container "$C" nspawn > "/srv/$C/$C.nspawn"
    
    ## write out config to a file accessible inside containers
    out container "$C" > "/var/srvctl3/share/containers/$C/config"
    
    ## TODO implement with hooks
    ## add codepad
    if [[ -d /usr/local/share/boilerplate ]]
    then
        echo 'BindReadOnly=/usr/local/share/boilerplate' >> "/srv/$C/$C.nspawn"
    fi
    
    for f in /srv/$C/*.binds
    do
        if [[ -f $f ]]
        then
            msg "Adding extra bind to nspawn ($f)"
            cat "$f" >> "/srv/$C/$C.nspawn"
        fi
    done
    
    ## create a shell file for firewalld configuration
    cfg container "$C" container_firewall_commands > /srv/"$C"/firewall_cmd.sh
    # shellcheck disable=SC1090
    source /srv/"$C"/firewall_cmd.sh
    
}

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
