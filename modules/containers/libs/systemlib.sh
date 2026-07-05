#!/bin/bash

##
##   containers/libs/systemlib.sh — render per-container systemd/nspawn
##   configuration from the datastore, and the template unit itself.
##
##   create_nspawn_container_config is the central renderer (also invoked
##   at every unit start via execstartpre.sh -> 'srvctl exec-function');
##   create_srvctl_nspawn_service writes the srvctl-nspawn@.service
##   template on update-install. All heredoc/unit content is a contract —
##   keep it byte-identical unless the campaign says otherwise.
##

## FIXME(v4): dead code — create_userslice_config has no callers; its
## limits also duplicate (and disagree with) the unit's CPUQuota below.
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


## Render everything nspawn needs for one container from the datastore:
## $C.nspawn, the network/ drop-ins, the hosts file, extra bind lines,
## ethernet.sh and firewall_cmd.sh (the latter sourced immediately).
## Order matters: the base nspawn file is written first, BindReadOnly
## and *.binds lines are appended after.
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

    ## bridge-attached containers additionally get DHCP on host0
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

    ## append order is a contract: /srv/$C/*.binds first, binds/*.binds after
    for f in "/srv/$C"/*.binds
    do
        if [[ -f $f ]]
        then
            msg "Adding extra bind to nspawn ($f)"
            cat "$f" >> "/srv/$C/$C.nspawn"
        fi
    done

    for f in "/srv/$C"/binds/*.binds
    do
        if [[ -f $f ]]
        then
            msg "Adding extra bind to nspawn ($f)"
            cat "$f" >> "/srv/$C/$C.nspawn"
        fi
    done

    ## create a shell file for ethernet configuration
    get container "$C" ethernet > /srv/"$C"/ethernet.sh

    ## create a shell file for firewalld configuration (applied right away)
    get container "$C" firewall_commands > /srv/"$C"/firewall_cmd.sh
    # shellcheck disable=SC1090 ## generated-file
    source /srv/"$C"/firewall_cmd.sh

}

## FIXME(v4): dead code — no callers; would only re-run every container's
## ethernet.sh.
function create_nspawn_container_configs() {

	for C in $(get cluster container_list)
	do
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

## Write the template unit for all containers. Contract highlights:
## Type=notify with SuccessExitStatus=133 (nspawn's reboot exit),
## ExecStartPre/Post/StopPost call this module's execstart*.sh scripts,
## resource caps CPUQuota=800%/MemoryMax=16G, DevicePolicy=closed.
function create_srvctl_nspawn_service {

    ## FIXME(v4): idempotence check tests /usr/lib/... but the unit is
    ## written to /etc/systemd/system — it never matches, so every
    ## update-install rewrites (and clobbers any admin-customized) unit.
    if [[ -f /usr/lib/systemd/system/srvctl-nspawn@.service ]]
    then
        msg "The srvctl-nspawn@.service configuration file is already installed."
        return
    fi

    msg "Create srvctl-nspawn@.service"

    ## this file resambles systemd-nspawn@.service with some tuning
    ## (unquoted heredoc: $SRVCTL, $NOW and $SC_INSTALL_DIR are baked in
    ## at generation time)
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



## Materialize the container's bridge in /run/systemd/network (volatile —
## recreated after boot by regenerate/unit start) and restart networkd.
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


## Network drop-ins present in every container: DHCP on zerotier
## bridge-endpoint interfaces (zt-*).
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