#!/bin/bash

function add_ve() { ## type name [bridge]
    
    local T C B
    T="$1"
    C="$2"
    B="$3"
    
    if [[ ! -d $SC_ROOTFS_DIR/$T ]]
    then
        err "No base for rootfs $T. Please run: srvctl regenerate rootfs"
        exit 10
    fi
    
    if [[ "$(get container "$C" exist)" == true ]]
    then
        err "$C already exists"
        exit 11
    fi
    
    ## check for a mistake
    if [[ -d /srv/$C/rootfs ]]
    then
        err "/srv/$C already exists! Exiting"
        exit 12
    fi
    
    ## TODO
    ## if the first 12 characters of the domain match against against a containers first 12 characters, then nspawn will fail to assign the vb- interface
    ## Failed to add new veth interfaces (vb-alpha-test.:host0): File exists
    ## alpha-test.domain1.ve alpha-test.domain2.ve
    
    ## Workaround is to use NetworkvethExtra
    ## add a "test" interface
    ## ip link set dev test up
    ## brctl addif 10.110.24.x test
    
    ## add to database
    new container "$C" "$T" "$B"
    exif "Could not add container to datastore."
    
    msg "$T container $C added to datastore."
    
    run_hooks add_ve_create_nspawn_container "$C"
    
    ## make local container
    create_nspawn_container_filesystem "$C"
    create_nspawn_container_config "$C"
    
    add_ve_certificate "$C"
    
    ## use a selfsigned certificate temporary
    cat "/srv/$C/cert/$C.pem" > "/var/srvctl3/datastore/cert/$C.pem"
    
    setup_index_html "$C" "/srv/$C/rootfs/var/www/html"
    write_ve_postfix_conf "$C"
    
    ln -s "/usr/lib/systemd/system/httpd.service" "/srv/$C/rootfs/etc/systemd/system/multi-user.target.wants/httpd.service"
    
    run systemctl enable "srvctl-nspawn@$C"
    if run systemctl start "srvctl-nspawn@$C" --no-pager
    then
        run systemctl status "srvctl-nspawn@$C" --no-pager
    else
        err "Failed to start container."
        run journalctl -u "srvctl-nspawn@$C" --no-pager
        err "Exiting due to an error."
        exit 17
    fi
    
}

## TODO detect if domain has a wildcard certificate
function add_ve_certificate() {
    local C
    C="$1"
    msg "Add VE certificate"
    create_selfsigned_domain_certificate "$C" "/srv/$C/cert"
    cat "/srv/$C/cert/$C.crt" > "/srv/$C/rootfs/etc/pki/tls/certs/localhost.crt"
    cat "/srv/$C/cert/$C.key" > "/srv/$C/rootfs/etc/pki/tls/private/localhost.key"
}