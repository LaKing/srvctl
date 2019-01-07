#!/bin/bash

function add_ve() { ## type name
    
    local T C
    T="$1"
    C="$2"
    
    
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
    
    ## add to database
    new container "$C" "$T"
    exif "Could not add container to datastore."
    
    msg "$T container $C added to datastore."
    
    run_hooks add_ve_create_nspawn_container "$T" "$C"
    
    ## make local container
    create_nspawn_container_filesystem "$T" "$C"
    create_nspawn_container_network "$T" "$C"
    
    create_selfsigned_domain_certificate "$C" "/srv/$C/cert"
    cat "/srv/$C/cert/$C.crt" > "/srv/$C/rootfs/etc/pki/tls/certs/localhost.crt"
    cat "/srv/$C/cert/$C.key" > "/srv/$C/rootfs/etc/pki/tls/private/localhost.key"
    
    setup_index_html "$C" "/srv/$C/rootfs/var/www/html"
    write_ve_postfix_conf "$C"
    
    ln -s "/srv/$C/rootfs/usr/lib/systemd/system/httpd.service" "/srv/$C/rootfs/etc/systemd/system/multi-user.target.wants/httpd.service"
    run systemctl start "srvctl-nspawn@$C" --no-pager
    run systemctl status "srvctl-nspawn@$C" --no-pager
    
}
