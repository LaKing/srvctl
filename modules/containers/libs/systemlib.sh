#!/bin/bash

function create_userslice_config() {
    
    msg "Create user-* slice configuration"
    
    mkdir -p /etc/systemd/system/user-.slice.d
    
cat > /etc/systemd/system/user-.slice.d/50-srvctl.conf << EOF
[Slice]
CPUQuota=400%
MemoryMax=16G
MemoryHigh=8G
EOF
    
    run systemctl daemon-reload
    
}


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
   
   	create_default_network_files "$C"
    
    ## custom bridge
    bridge="$(get container "$C" bridge)"
    
    msg "Using the default virtual ethernet configuration for $C"
    get container "$C" ethernet_network > "/srv/$C/network/srvctl-ethernet.network"
        
    create_networkd_bridge "$C"
       
    if [[ $bridge != false ]]
    then
        msg "Using bridge $bridge with host0 interface (DHCP). for $C"

cat > "/srv/$C/network/80-container-host0.network" << EOF
[Match]
Virtualization=container
Name=host0

[Network]
DHCP=yes

[DHCP]
UseTimezone=yes
EOF

    fi
    
    get container "$C" hosts > "/srv/$C/hosts"
    #get container "$C" resolv_conf > "/srv/$C/rootfs/etc/resolv.conf"
    
    
    ## TODO implement with hooks
    ## add codepad
    if [[ -d /usr/local/share/boilerplate ]]
    then
    	## TODO this now bp-devel specific, it should be generally in a module
        echo 'BindReadOnly=/srv/v3-devel/rootfs/srv/boilerplate:/usr/local/share/boilerplate' >> "/srv/$C/$C.nspawn"
	fi
    
    if [[ -d /usr/local/share/codepad ]]
    then
        echo 'BindReadOnly=/srv/c3-devel/rootfs/srv/codepad:/usr/local/share/codepad' >> "/srv/$C/$C.nspawn"
	fi
    
    for f in /srv/$C/*.binds
    do
        if [[ -f $f ]]
        then
            msg "Adding extra bind to nspawn ($f)"
            cat "$f" >> "/srv/$C/$C.nspawn"
        fi
    done 
    
    for f in /srv/$C/binds/*.binds
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

function create_nspawn_container_configs() {

	for C in $(get cluster container_list)
	do
    	#create_nspawn_container_config "$C"
        /bin/bash /srv/"$C"/ethernet.sh
    done
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
    
    if [[ -f /usr/lib/systemd/system/srvctl-nspawn@.service ]]
    then
        msg "The srvctl-nspawn@.service configuration file is already installed."
        return
    fi
    
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

## enforce limits
CPUQuota=800%
MemoryMax=16G
MemoryHigh=8G

[Install]
WantedBy=machines.target

EOF
    
    systemctl daemon-reload
}



function create_networkd_bridge { ## C
    local C br
    C="$1"
    br="$(get container "$C" br)" || return
    mkdir -p /run/systemd/network
    
    if [[ -f "/run/systemd/network/br-$br.netdev" ]] && [[ -f "/run/systemd/network/br-$br.network" ]]
    then
    	ntc "Bridge $br exists"
        return
    fi
    
    if [[ "$(get container "$C" deprecated)" == true ]]
    then
    	ntc "Container is deprecated, not creating the bridge"
    	return
    fi
    
    msg "Creating network bridge $br"
    
    get container "$C" br_netdev > "/run/systemd/network/br-$br.netdev"
    get container "$C" br_network > "/run/systemd/network/br-$br.network"
    
    run systemctl restart systemd-networkd --no-pager
}


function create_default_network_files { ## C
	local C
    C=$1

cat > "/srv/$C/network/zt-bridge-endpoint.network" << EOF
[Match]
Name=zt-*

[Network]
DHCP=yes
EOF
}