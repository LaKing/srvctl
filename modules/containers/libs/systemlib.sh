#!/bin/bash


function create_nspawn_container_config() { ## Container
    
    ## does the action on /srv
    
    local br bridge C
    C="$1"
    
    msg "Create nspawn container config for $C"
    
    ## create the nspawn file
    get container "$C" nspawn > "/srv/$C/$C.nspawn"
    
    create_nspawn_container_settings "$C"
    
    rm -fr "/srv/$C/network"
    mkdir -p "/srv/$C/network"
    
    ## custom bridge
    bridge="$(get container "$C" bridge)"
    
    if [[ $bridge == false ]]
    then
        msg "Using the default virtual ethernet configuration for $C"
        get container "$C" ethernet_network > "/srv/$C/network/ethernet.network"
        
        create_networkd_bridge "$C"
    else
        msg "Using bridge $bridge with host0 interface (DHCP). for $C"
        get container "$C" ethernet_network > "/srv/$C/network/80-container-host0.network"
        #cat /usr/lib/systemd/network/80-container-host0.network > "/srv/$C/network/80-container-host0.network"
    fi
    
    get container "$C" hosts > "/srv/$C/hosts"
    get container "$C" resolv_conf > "/srv/$C/rootfs/etc/resolv.conf"
    
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
    
    ## create a shell file for ethernet configuration
    get container "$C" ethernet > /srv/"$C"/ethernet.sh
    
    ## create a shell file for firewalld configuration
    get container "$C" firewall_commands > /srv/"$C"/firewall_cmd.sh
    # shellcheck disable=SC1090
    source /srv/"$C"/firewall_cmd.sh
    
}


function create_nspawn_container_settings { ## container
    
    ## does the action on /var
    
    local C
    C="$1"
    
    msg "Create nspawn container settings for $C"
    
    mkdir -p "/var/srvctl3/share/containers/$C/users"
    
    ## write out config to a file accessible inside containers
    out container "$C" > "/var/srvctl3/share/containers/$C/config"
    
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



function create_networkd_bridge { ## C
    local C br
    C="$1"
    br="$(get container "$C" br)" || return
    
    if [[ -f "/etc/systemd/network/br-$br.netdev" ]] && [[ -f "/etc/systemd/network/br-$br.network" ]]
    then
        return
    fi
    
    msg "Creating network bridge $br"
    
    get container "$C" br_netdev > "/etc/systemd/network/br-$br.netdev"
    get container "$C" br_network > "/etc/systemd/network/br-$br.network"
    
    run systemctl restart systemd-networkd --no-pager
}


