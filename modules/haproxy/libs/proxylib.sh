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
## except for the hourly cron run (ARG '#cron.hourly'), which reloads only
## when the served certificate set changed since the last reload.
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

    ## Select + sync the certs haproxy serves: prefer a matching WILDCARD over a
    ## per-domain (letsencrypt) cert, keep only valid certs, and PRUNE stale /
    ## superseded copies so a renewal is never shadowed by an old one (this
    ## replaces the add-only `cp -u` that never pruned). certselectlib lives in
    ## the certificates module; fall back to the old behaviour if it is not
    ## loaded on this host.
    if command -v sync_haproxy_certificates > /dev/null 2>&1
    then
        sync_haproxy_certificates /var/haproxy
    else
        load_certificate_folder_files /var/srvctl3/datastore/cert
        for sccert_dir in /etc/srvctl/cert/*
        do
            load_certificate_folder_files "$sccert_dir"
        done
        ## the CA bundle is not a servable certificate; keep it out of the
        ## crt directory haproxy binds to
        rm -fr /var/haproxy/ca-bundle.pem
    fi

    haproxycfg
    ## reload (not restart) keeps existing connections alive. The hourly cron
    ## run still skips it, unless the served certificate set differs from the
    ## one haproxy last loaded (a renewal or a new wildcard): then it reloads
    ## too, so renewals become active without manual action.
    if [[ $ARG == "#cron.hourly" ]] && ! haproxy_certificates_changed
    then
        msg "Skipping reload for automatic regeneration #cron.hourly"
    elif reload_haproxy
    then
        haproxy_record_reloaded
    else
        ## keep the previous record: the next hourly run sees the change
        ## and retries the reload
        err "haproxy did not load the new certificate set; the next run retries"
    fi
}

## haproxy_certificates_listing: checksum listing of the served cert dir.
function haproxy_certificates_listing {
    local dir="${SC_HAPROXY_CERT_DIR:-/var/haproxy}" f
    for f in "$dir"/*.pem
    do
        [[ -f "$f" ]] || continue
        sha256sum -- "$f"
    done | LC_ALL=C sort
}

## haproxy_certificates_changed: 0 when the served certificate set differs
## from the listing recorded after the last successful reload (or none was
## recorded). The record lives outside the crt directory, which haproxy loads
## whole. A crash between the certificate sync and the reload leaves the old
## record, so the next run still reloads.
function haproxy_certificates_changed {
    local record="${SC_HAPROXY_RELOADED_LIST:-/var/srvctl3/acme/haproxy-reloaded.list}"
    [[ -f "$record" ]] || return 0
    [[ "$(haproxy_certificates_listing)" != "$(cat "$record")" ]]
}

## haproxy_record_reloaded: remember what haproxy now serves. Called only
## after reload_haproxy reported the reload loaded; still refuses when the
## unit is not running.
function haproxy_record_reloaded {
    local record="${SC_HAPROXY_RELOADED_LIST:-/var/srvctl3/acme/haproxy-reloaded.list}"
    systemctl is-active --quiet haproxy.service || return 0
    mkdir -p "${record%/*}"
    haproxy_certificates_listing > "$record.tmp.$$" && mv -f "$record.tmp.$$" "$record"
}
