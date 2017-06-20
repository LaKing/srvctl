#!/bin/bash

function nfs_generate_exports { # for container
    
    ## Ip is the bridge address with 1 instead of x
    local C bridge
    
    C="$1"
    bridge="$(get container "$C" br_host_ip)"
    
cat > "/srv/$C/rootfs/etc/exports" << EOF
## srvctl generated
/var/log $bridge(ro)
/srv $bridge(rw,all_squash,anonuid=101,anongid=101)
/var/git $bridge(rw,all_squash,anonuid=102,anongid=102)
/var/www/html $bridge(rw,all_squash,anonuid=48,anongid=48)
EOF
    
}
