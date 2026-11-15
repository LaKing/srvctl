#!/bin/bash

##
##   containers/libs/addcontainerlib.sh — container creation core.
##
##   add_ve builds a complete container from a base image; used by
##   add-ve, add-network-ve and the codepad module's add-codepad. Exit
##   codes are contracts: 22 invalid name, 10 no base image, 11 datastore
##   record exists, 13 the name is a domain of another container, 12 /srv
##   dir exists, 17 unit failed to start.
##

## A container name is a host name: haproxy routes it, named serves it, and
## systemd-nspawn takes it as the machine name (64 characters at most). It
## also becomes a path below /srv and a unit instance name.
function valid_container_name { ## NAME
    [[ ${#1} -le 64 ]] && [[ $1 =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$ ]]
}

## Print the container that already serves NAME or www.NAME (as its name, an
## alias, an altname or a subdomain). Two containers on one host name would
## give haproxy two backends for it and request its certificate twice.
function container_domain_owner { ## NAME
    local C cell rows
    rows="$(list container domains)" || return $?
    while IFS=$'\t' read -r C cell
    do
        ## the cell is a JSON list, so "NAME" in quotes is one whole element
        if [[ $C == "$1" ]] || [[ $cell == *"\"$1\""* ]] || [[ $cell == *"\"www.$1\""* ]]
        then
            printf '%s\n' "$C"
            return 0
        fi
    done <<< "$rows"
    return 0
}

function add_ve() { ## type name [bridge]

    local T C B owner
    T="$1"
    C="$2"
    B="$3"

    ## Both arrive from the command line of any user and end up in paths.
    if ! valid_container_name "$C"
    then
        err "Invalid container name: $C (a lowercase host name such as example.com, 64 characters at most)"
        exit 22
    fi
    if [[ ! $T =~ ^[a-z0-9][a-z0-9._-]*$ ]] || [[ ! -f $SC_ROOTFS_DIR/$T/etc/os-release ]]
    then
        err "No base image '$T'. Available: $(cd "$SC_ROOTFS_DIR" 2> /dev/null && echo *)"
        exit 10
    fi

    if [[ "$(get container "$C" exist)" == true ]]
    then
        err "$C already exists"
        exit 11
    fi

    owner="$(container_domain_owner "$C")"
    exif "Could not check the domains in use."
    if [[ -n $owner ]]
    then
        err "$C is already served by the container $owner"
        exit 13
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
    
    init_ve_rootfs "$C"

    ## use a selfsigned certificate temporary
    cat "/srv/$C/cert/$C.pem" > "${SC_DATASTORE_DIR:?}/cert/$C.pem"

    setup_index_html "$C" "/srv/$C/rootfs/var/www/html"

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

## Per-container setup of a freshly copied base image, before its first start.
## Shared by add_ve and rebuild_ve (libs/rebuildlib.sh), which must not touch
## the datastore certificate.
function init_ve_rootfs() { ## C
    local C
    C="$1"

    add_ve_certificate "$C"
    write_ve_postfix_conf "$C"

    [[ -e "/srv/$C/rootfs/etc/systemd/system/multi-user.target.wants/httpd.service" ]] \
        || ln -s "/usr/lib/systemd/system/httpd.service" "/srv/$C/rootfs/etc/systemd/system/multi-user.target.wants/httpd.service"

    ## there is a bug somehwere, this is a hotfix
    cat "/usr/local/share/srvctl/modules/containers/conf/resolved.conf" > "/srv/$C/rootfs/etc/systemd/resolved.conf"
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
        ## before the first start: PrivateUsersChown shifts the owner then
        chmod 600 "/srv/$C/rootfs/etc/pki/tls/private/localhost.key"
    fi
}