#!/bin/bash

function create_nspawn_container_service {
    
    local C bridge
    C="$1"
    bridge="$2"
    
    mkdir -p /etc/srvctl/containers
cat > "/etc/srvctl/containers/$C.service" << EOF
# container: $C bridge: $bridge host: $HOSTNAME date: $NOW user: $SC_USER
[Unit]
Description=Container $C
Documentation=man:systemd-nspawn(1)
PartOf=machines.target
Before=machines.target
After=network.target

[Service]
# ExecStart=/usr/bin/systemd-nspawn --quiet --keep-unit --boot --link-journal=try-guest --network-bridge=$bridge -U --settings=override --machine=$C -D /srv/$C/rootfs
ExecStart=$SC_INSTALL_DIR/modules/containerfarm/execstart.sh $C
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
    
    systemctl enable "/etc/srvctl/containers/$C.service"
    #systemctl daemon-reload
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

#function create_networkd_bridges { ## net
#    local a b
#    a=10
#    b=$(( $SC_HOSTNET * 16 ))
#
#     for c in {0..250}
#     do
#         create_networkd_bridge "$a" "$b" "$c"
#     done
#
#    systemctl restart systemd-networkd --no-pager
#}


function create_nspawn_container_host0 {
    local C gw ip br
    C="$1"
    br="$2"
    ## here I assume that the bridge always ends in .x and the gateway adress, (bridge adress) is .1
    gw="${br::-1}1"
    ip="$3"
    
cat > "/srv/$C/rootfs/etc/systemd/network/80-container-host0.network" << EOF
[Match]
Virtualization=container
Name=host0

[Network]
Address=$ip/24
Gateway=$gw

EOF
    
}
