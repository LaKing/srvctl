#!/bin/bash

##
##   haproxy/libs/proxylib.sh — certificate loading and config regeneration.
##
##   Sourced by load_libs when the haproxy module is enabled.
##   regenerate_haproxy_conf is the module's main entry point, called from
##   the redirect commands, hooks/regenerate.sh, and cross-module by
##   named/commands/override-in-address.sh.
##

## load_certificate_folder_files DIR: for each DIR/*.pem run check_pem
## (certificates module — deletes certs expiring within 7 days, always
## returns 0), then copy surviving files into /var/haproxy (cp -u: only
## when newer). An empty DIR leaves the unmatched glob to fail the -f
## re-check harmlessly.
## FIXME(v4): check_pem deletes admin-managed SOURCE certificates up to 7
## days before expiry (hourly via cron), while the stale /var/haproxy copy
## is never pruned and keeps being served; cert sync belongs to the
## certificates module.
function load_certificate_folder_files {
    local certdir
    local cert
    certdir="$1"

    for cert in "$certdir"/*.pem
    do
        if check_pem "$cert"
        then
            if [[ -f "$cert" ]]
            then
                cp -u "$cert" /var/haproxy/
            fi
        fi
    done
}


## regenerate_haproxy_conf: refresh /var/haproxy certificates, re-render
## /etc/haproxy/haproxy.cfg via haproxycfg, then reload the service —
## except for the hourly cron run (ARG '#cron.hourly'), which deliberately
## regenerates without reloading.
function regenerate_haproxy_conf {
    ## static ve-host-certificates with priority from etc
    ## container certificates from gluster share

    local sccert_dir

    ## FIXME(v4): SC_DATASTORE_DIR may resolve to the read-only gluster dir,
    ## an inconsistent pair with the hardcoded rw path below.
    mkdir -p "$SC_DATASTORE_DIR/cert"
    mkdir -p "$SC_DATASTORE_DIR/pki-validation"

    msg "Regenerate haproxy configs."
    ## the haproxy certificates will be loaded from /var/haproxy
    mkdir -p /var/haproxy
    ## we may have server-wide wildcard certificates
    mkdir -p /etc/srvctl/cert

    ## FIXME(v4): hardcoded path — should honor SC_DATASTORE_RW_DIR.
    load_certificate_folder_files /var/srvctl3/datastore/cert

    for sccert_dir in /etc/srvctl/cert/*
    do
        load_certificate_folder_files "$sccert_dir"
    done

    ## the CA bundle is not a servable certificate; keep it out of the
    ## crt directory haproxy binds to
    rm -fr /var/haproxy/ca-bundle.pem

    haproxycfg
    ## reload (not restart) keeps existing connections alive
    if [[ $ARG == "#cron.hourly" ]]
    then
        msg "Skipping reload for automatic regeneration #cron.hourly"
    else
        reload_haproxy
    fi
}
