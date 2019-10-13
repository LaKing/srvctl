#!/bin/bash


function create_container_config() { ## Container
    
    local br bridge C
    C="$1"
    
    create_nspawn_container_settings "$C"
    
    mkdir -p "/srv/$C/network"
    
    ## if we have a custom bridge use that, no need to go further
    bridge="$(get container "$C" bridge)"
    
    if [[ $bridge == FALSE ]]
    then
        msg "Using the default virtual ethernet configuration."
        cfg container "$C" ethernet_network > "/srv/$C/network/ethernet.network"
        cfg container "$C" hosts > "/srv/$C/hosts"
        cfg container "$C" resolv_conf > "/srv/$C/rootfs/etc/resolv.conf"
        
        create_networkd_bridge "$C"
    else
        msg "Using bridge $bridge with host0 interface (DHCP)."
        #cfg container "$C" ethernet_network > "/srv/$C/network/80-container-host0.network"
        cat /usr/lib/systemd/network/80-container-host0.network > "/srv/$C/network/80-container-host0.network"
    fi
}

function create_srvctl_nspawn_service {
    
    ## TODO remove, this is just temporary
    rm -fr /usr/lib/systemd/system/srvctl-nspawn@.service
    
    msg "Create srvctl-nspawn@.service"
    
    ## this file resambles systemd-nspawn@.service with some tuning
cat > "/etc/systemd/system/srvctl-nspawn@.service" << EOF
# $SRVCTL $NOW
[Unit]
Description=srvctl - container %i
Documentation=man:systemd-nspawn(1)
PartOf=machines.target
Before=machines.target
After=network.target systemd-resolved.service
RequiresMountsFor=/var/lib/machines

[Service]
ExecStartPre=/bin/bash $SC_INSTALL_DIR/modules/containers/execstartpre.sh %i
ExecStart=/usr/bin/systemd-nspawn --quiet --keep-unit --boot --link-journal=try-guest --settings=trusted --machine=%i -D /srv/%i/rootfs
ExecStartPost=/bin/bash $SC_INSTALL_DIR/modules/containers/execstartpost.sh %i
ExecStopPost=/bin/bash $SC_INSTALL_DIR/modules/containers/execstoppost.sh %i

KillMode=mixed
Type=notify
RestartForceExitStatus=133
SuccessExitStatus=133
WatchdogSec=3min
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

# nspawn can set up LUKS encrypted loopback files, in which case it needs
# access to /dev/mapper/control and the block devices /dev/mapper/*.
DeviceAllow=/dev/mapper/control rw
DeviceAllow=block-device-mapper rw

[Install]
WantedBy=machines.target

EOF
    
    systemctl daemon-reload
}



function create_networkd_bridge { ## for container
    local C br
    C="$1"
    br="$(get container "$C" br)" || return
    
    if [[ -f "/etc/systemd/network/br-$br.netdev" ]] && [[ -f "/etc/systemd/network/br-$br.network" ]]
    then
        return
    fi
    
    msg "Creating network bridge $br"
    
    cfg container "$C" br_netdev > "/etc/systemd/network/br-$br.netdev"
    cfg container "$C" br_network > "/etc/systemd/network/br-$br.network"
    
    run systemctl restart systemd-networkd --no-pager
}


