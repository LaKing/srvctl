#!/bin/bash

function create_nspawn_container_settings { ## container ## bridge
    
    local C
    C="$1"
    br="$2"
    if [[ -z $br ]]
    then
        br="$(get container "$C" br)"
        ## TODO ensure bridge is created and exists
        
    fi
    uid="$(get container "$C" uid)"
    
    msg "Create nspawn container settings for $C $br ($uid)"
    
    mkdir -p "/var/srvctl3/share/containers/$C/users"
    
    ## mapped ports allow applications to connect to certain containers.
    
cat > "/srv/$C/$C.nspawn" << EOF
[Network]
Bridge=$br
$(cfg container "$C" mapped_ports)

[Exec]
#PrivateUsers=$uid

[Files]
#PrivateUsersChown=true
BindReadOnly=$SC_INSTALL_DIR

BindReadOnly=/var/srvctl3/share/containers/$C
BindReadOnly=/var/srvctl3/share/common

BindReadOnly=/srv/$C/network:/etc/systemd/network
#BindReadOnly=/var/srvctl3/share/lock:/usr/lib/systemd/network
BindReadOnly=/var/srvctl3/share/lock:/run/systemd/network
BindReadOnly=/srv/$C/hosts:/etc/hosts

EOF

	out container "$C" > "/var/srvctl3/share/containers/$C/config"
        
    ## add codepad
    if [[ -d /usr/local/share/boilerplate ]]
    then
        echo 'BindReadOnly=/usr/local/share/boilerplate' >> "/srv/$C/$C.nspawn"
    fi
    
    
    ## add codepad - legacy at th emoment
    #if [[ -d /var/codepad/boilerplate ]]
    #then
    #    echo 'BindReadOnly=/var/codepad/boilerplate' >> "/srv/$C/$C.nspawn"
    #fi
    
    for f in /srv/$C/*.binds
    do
        if [[ -f $f ]]
        then
            msg "Adding extra bind to nspawn ($f)"
            cat "$f" >> "/srv/$C/$C.nspawn"
        fi
    done
    
    
    cfg container "$C" container_firewall_commands > /srv/"$C"/firewall_cmd.sh
    # shellcheck disable=SC1090
    source /srv/"$C"/firewall_cmd.sh
    
}

function update_nspawn_container { ## container
    
    local C
    C="$1"
    
    
    run ssh "$C" "dnf -y install kernel kernel-modules kernel-core kernel-headers dnf-plugin-system-upgrade"
    run ssh "$C" "dnf -y upgrade --refresh"
    run ssh "$C" "dnf -y system-upgrade download --refresh --releasever=28"
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
