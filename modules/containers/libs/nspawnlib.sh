#!/bin/bash

function create_nspawn_container_settings { ## container ## bridge
    
    local C
    C="$1"
    br="$2"
    if [[ -z $br ]]
    then
        br="$(get container "$C" br)" || exit
    fi
    uid="$(get container "$C" uid)"
    
    msg "Create nspawn container settings for $C $br ($uid)"
    
    mkdir -p "/var/srvctl3/share/containers/$C/users"
    
    
cat > "/srv/$C/$C.nspawn" << EOF
[Network]
Bridge=$br

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

if [[ -d /var/codepad/boilerplate ]]
then
    echo 'BindReadOnly=/var/codepad/boilerplate' >> "/srv/$C/$C.nspawn"
fi

if [[ ! -z $(ls /srv/"$C" | grep '.binds') ]]
then
    msg "Adding extra binds to nspawn"
    cat /srv/$C/*.binds >> "/srv/$C/$C.nspawn"
fi
    
}

function update_nspawn_container { ## container
    
    local C
    C="$1"
    
    
    run ssh "$C" "dnf -y install kernel kernel-modules kernel-core kernel-headers dnf-plugin-system-upgrade"
    run ssh "$C" "dnf -y upgrade --refresh"
    run ssh "$C" "dnf -y system-upgrade download --refresh --releasever=27"
    #exif
    run ssh "$C" "dnf -y system-upgrade reboot"
    sleep 3
    run systemctl status srvctl-nspawn@"$C" --no-pager
    run systemctl is-active srvctl-nspawn@$C
    sleep 3
    if [[ "$(systemctl is-active srvctl-nspawn@$C)" != active ]]
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
