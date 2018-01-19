#!/bin/bash


function create_container_config() { ## Container
    
    local ip br C
    C="$1"
    ip="$(get container "$C" ip)" || exit
    br="$(get container "$C" br)" || exit
    
    create_networkd_bridge "$br"
    create_nspawn_container_host0 "$C" "$br" "$ip"
    create_nspawn_container_hostsfile "$C" "$br" "$ip"
    create_nspawn_container_settings "$C" "$br"
    
}

function create_srvctl_nspawn_service {
    
    ## TODO remove
    rm -fr /usr/lib/systemd/system/srvctl-nspawn@.service
    
cat > "/etc/systemd/system/srvctl-nspawn@.service" << EOF
# container: $C bridge: $bridge host: $HOSTNAME date: $NOW user: $SC_USER
[Unit]
Description=srvctl - container %i
Documentation=man:systemd-nspawn(1)
PartOf=machines.target
Before=machines.target
After=network.target

[Service]
ExecStartPre=/bin/bash $SC_INSTALL_DIR/modules/containers/execstartpre.sh %i
ExecStart=/usr/bin/systemd-nspawn --quiet --keep-unit --boot --link-journal=try-guest --settings=trusted --machine=%i -D /srv/%i/rootfs
ExecStartPost=/bin/bash $SC_INSTALL_DIR/modules/containers/execstartpost.sh %i
ExecStopPost=/bin/bash $SC_INSTALL_DIR/modules/containers/execstoppost.sh %i

KillMode=mixed
Type=notify
RestartForceExitStatus=133
SuccessExitStatus=133
Slice=machine.slice
Delegate=yes
TasksMax=16384

# Enforce a strict device policy, similar to the one nspawn configures
# when it allocates its own scope unit. Make sure to keep these
# policies in sync if you change them!
DevicePolicy=closed
DeviceAllow=/dev/net/tun rwm
DeviceAllow=char-pts rw

# nspawn itself needs access to /dev/loop-control and /dev/loop, to
# implement the --image= option. Add these here, too.
DeviceAllow=/dev/loop-control rw
DeviceAllow=block-loop rw
DeviceAllow=block-blkext rw

[Install]
WantedBy=machines.target

EOF
    
    systemctl daemon-reload
}



function create_networkd_bridge { ## br
    local br gw
    br="$1"
    gw="${br::-1}1"
    
    if [[ -f "/etc/systemd/network/br-$br.netdev" ]] && [[ -f "/etc/systemd/network/br-$br.network" ]]
    then
        return
    fi
    
    msg "Creating network bridge $br"
    
cat > "/etc/systemd/network/br-$br.netdev" << EOF
[NetDev]
Name=$br
Kind=bridge

EOF
    
cat > "/etc/systemd/network/br-$br.network" << EOF
[Match]
Name=$br

[Network]
IPMasquerade=yes
Address=$gw/24

EOF
    
    run systemctl restart systemd-networkd --no-pager
}



function create_nspawn_container_host0 {
    local C gw ip br
    C="$1"
    br="$2"
    ## here I assume that the bridge always ends in .x and the gateway adress, (bridge adress) is .1
    gw="${br::-1}1"
    ip="$3"
    
    ## cat > "/srv/$C/rootfs/etc/systemd/network/80-container-host0.network" << EOF
    mkdir -p "/srv/$C/network"
cat > "/srv/$C/network/80-container-host0.network" << EOF
[Match]
Virtualization=container
Name=host0

[Network]
Address=$ip/24
Gateway=$gw

EOF
    
}


function create_nspawn_container_hostsfile {
    local C gw ip br
    C="$1"
    br="$2"
    gw="${br::-1}1"
    ip="$3"
    
    
cat > "/srv/$C/hosts" << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

$ip $C
$gw srvctl-gateway

EOF
    
}

