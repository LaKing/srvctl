#!/bin/bash

##
##   containers/libs/addcontainerlib.sh — container creation core.
##
##   add_ve builds a complete container from a base image; used by
##   add-ve, add-network-ve and the codepad module's add-codepad. Exit
##   codes are contracts: 10 no base image, 11 datastore record exists,
##   12 /srv dir exists, 17 unit failed to start.
##

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
    
    ## if the first 12 characters of the domain match against against a containers first 12 characters, then nspawn will fail to assign the vb- interface
    ## Failed to add new veth interfaces (vb-alpha-test.:host0): File exists
    ## alpha-test.domain1.ve alpha-test.domain2.ve
    
    ## Workaround is to use NetworkvethExtra
    ## add a "test" interface
    ## ip link set dev test up
    ## brctl addif 10.110.24.x test
    
    ## add to database
    ## TODO - implement with hooks
    ## contract: type 'codepad' is stored as 'fedora' in the datastore
    ## (codepad containers are fedora images customized by hooks)
    if [[ $T == codepad ]]
    then
        new container "$C" fedora "$B"
    else
        new container "$C" "$T" "$B"
    fi

    exif "Could not add container to datastore."
    
    msg "$C added to the datastore."
    
    run_hooks add_ve_create_nspawn_container "$C"
    
    ## make local container
    create_container_configuration_files "$C"
    create_nspawn_container_filesystem "$C" "$T"
    create_nspawn_container_config "$C"
    
    add_ve_certificate "$C"

    ## use a selfsigned certificate temporary
    ## FIXME(v4): 'run cat X > Y' redirects run's ANSI banner into the
    ## target file — the pem below and resolved.conf further down each get
    ## a garbage first line (tolerated by openssl/systemd today, breaks
    ## strict parsers); use plain cat.
    run cat "/srv/$C/cert/$C.pem" > "/var/srvctl3/datastore/cert/$C.pem"

    setup_index_html "$C" "/srv/$C/rootfs/var/www/html"
    write_ve_postfix_conf "$C"

    ln -s "/usr/lib/systemd/system/httpd.service" "/srv/$C/rootfs/etc/systemd/system/multi-user.target.wants/httpd.service"

    ## there is a bug somehwere, this is a hotfix
    run cat "/usr/local/share/srvctl/modules/containers/conf/resolved.conf" > "/srv/$C/rootfs/etc/systemd/resolved.conf"

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

## TODO detect if domain has a wildcard certificate? Nah, containers should not access wildcard certificates. Unless the cert owner is the container owner? Naah, better not.
function add_ve_certificate() {
    local C
    C="$1"
    
    ## this seems to be fedora-only
    if [[ -d "/srv/$C/rootfs/etc/pki/tls/certs" ]] && [[ -d "/srv/$C/rootfs/etc/pki/tls/private" ]]
    then
        msg "Add VE certificate"
        create_selfsigned_domain_certificate "$C" "/srv/$C/cert"
        cat "/srv/$C/cert/$C.crt" > "/srv/$C/rootfs/etc/pki/tls/certs/localhost.crt"
        cat "/srv/$C/cert/$C.key" > "/srv/$C/rootfs/etc/pki/tls/private/localhost.key"
    fi
}