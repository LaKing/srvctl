#!/bin/bash

function create_container_service {
    
    local C bridge
    C="$1"
    bridge="$2"
    
    mkdir -p /etc/srvctl/containers
cat > "/etc/srvctl/containers/$C.service" << EOF

[Unit]
Description=Container $C
Documentation=man:systemd-nspawn(1)
PartOf=machines.target
Before=machines.target
After=network.target

[Service]
ExecStart=/usr/bin/systemd-nspawn --quiet --keep-unit --boot --link-journal=try-guest --network-bridge=$bridge -U --settings=override --machine=$C
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

function create_container_bridge {
    local C bridge
    C="$1"
    bridge="$2"
    
cat > "/etc/systemd/network/br-$bridge.netdev" << EOF
## srvctl $C
[NetDev]
Name=$bridge
Kind=bridge

EOF
    
cat > "/etc/systemd/network/br-$bridge.network" << EOF
## srvctl $C
[Match]
Name=$bridge

[Network]
IPMasquerade=yes
Address=$bridge/28

EOF
    
    systemctl restart systemd-networkd --no-pager
}

function create_container_host0 {
    local C bridge ip
    C="$1"
    bridge="$2"
    ip="$3"
    
cat > "$SRV/$C/etc/systemd/network/80-container-host0.network" << EOF
[Match]
Virtualization=container
Name=host0

[Network]
Address=$ip/28
Gateway=$bridge

EOF
    
}
