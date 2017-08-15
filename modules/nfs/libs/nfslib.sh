#!/bin/bash

function nfs_generate_exports { # for host
    
cat > /etc/exports << EOF
## srvctl generated
/srv 10.15.0.0/255.255.0.0(rw,no_root_squash)
EOF
    
}

function nfs_mount() {
    
    msg "nfs mount"
    
    local hs
    for host in $(cfg cluster host_list)
    do
        if run showmount -e "$host"
        then
            run timeout 1 mkdir -p "/var/srvctl3/nfs/$host/srv"
            hs="$(get host "$host" hostnet)"
            msg "openvpn connection check to $host ($hs)"
            if run timeout 1 ping -c 1 -W 1 "10.15.$hs.1"
            then
                run "mount 10.15.$hs.1:/srv /var/srvctl3/nfs/$host/srv"
            else
                err "Could not ping 10.15.$hs.1"
            fi
        fi
    done
}