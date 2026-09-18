#!/bin/bash

##
##   letsencrypt/libs/letsencryptlib.sh — acme install and regenerate driver.
##
##   Sourced by load_libs whenever the letsencrypt module is enabled.
##   Provides:
##     install_acme            — update-install-host hook payload
##     regenerate_letsencrypt  — regenerate_certificates hook payload
##
##   Touches /etc/letsencrypt/{cli.ini,ca.pem,live/}, /var/srvctl3/acme
##   (DNS-01 handover state, bundles, status), /var/acme (challenge
##   webroot, owned acme:acme, uid 528), /etc/systemd/system/
##   acme-server.service and $SC_DATASTORE_DIR/cert/. The unit name
##   acme-server.service, the acme user, the /var/acme webroot and the
##   server's port 1028 are shared API: haproxy forwards the port-80
##   /.well-known/acme-challenge/ path to 127.0.0.1:1028.
##

## install_acme: one-shot host setup for the ACME http-01 workflow.
## Installs the certbot package (sc_install letsencrypt), writes
## /etc/letsencrypt/cli.ini (webroot authenticator on /var/acme), creates
## the acme system user and webroot, generates and starts
## acme-server.service (the port-1028 challenge responder behind haproxy)
## and removes any stale /etc/letsencrypt/ca.pem left by earlier versions. Runs on every
## update-install (twice, in fact — the certificates module hook also calls
## it); re-runs only regenerate the same files.
function install_acme {

    msg "Installing letsencrypt and the acme-server"

    ## install letsencrypt
    sc_install letsencrypt
    mkdir -p /etc/letsencrypt

    echo "## $SRVCTL generated
email = webmaster@$SC_COMPANY_DOMAIN
text = True
authenticator = webroot
webroot-path = /var/acme
    " > /etc/letsencrypt/cli.ini

    mkdir -p /var/acme
    ## FIXME(v4): useradd is unguarded — on re-install it prints
    ## "useradd: user 'acme' already exists" on stderr (non-fatal noise);
    ## guard with getent/id or wrap in eyif.
    useradd -r -u 528 -c "Letsencrypt-acme-server" acme
    chown acme:acme /var/acme

    echo "## $SRVCTL generated
[Unit]
Description=Letsencrypt server.
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node $SC_INSTALL_DIR/modules/letsencrypt/apps/acme-server.js
User=acme
Group=acme

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
    " > /etc/systemd/system/acme-server.service

    ## cleanup of the legacy unit location. TODO remove
    rm -fr /lib/systemd/system/acme-server.service

    ## Earlier versions installed a vendored DST Root CA X3 (expired
    ## 2021-09-30) here and letsencrypt.js appended it to every bundle.
    ## Nothing reads the file any more; a stale copy is removed so it cannot
    ## be mistaken for a live input.
    rm -f /etc/letsencrypt/ca.pem

    systemctl daemon-reload

    run systemctl enable acme-server.service
    run systemctl start acme-server.service
    run systemctl status acme-server.service --no-pager
}


## acme_snapshot_manifest: copy the committed DNS-01 zone manifest
## (named/libs/acmelib.sh) together with the hash of the live srvctl.conf,
## both read under a shared hold of the named activation lock, so the pair
## is consistent even while a named regenerate runs. letsencrypt.js issues
## DNS-01 only when the two hashes agree. No manifest (non-DNS host, or the
## _acme zone not set up yet) leaves no snapshot.
function acme_snapshot_manifest {
    local dir named conf lock
    dir="${SC_ACME_DIR:-/var/srvctl3/acme}"
    named="${SC_NAMED_STATE_DIR:-/var/srvctl3/named}"
    conf="${SC_NAMED_CONF:-/var/named/srvctl.conf}"
    lock="${SC_NAMED_ACTIVATE_LOCK:-/run/srvctl-named-activate.lock}"
    mkdir -p "$dir"
    rm -f "$dir/manifest.snapshot.json" "$dir/manifest.live.sha256"
    [[ -f "$named/acme-zones.json" ]] || return 0
    # shellcheck disable=SC2016 # expanded by the inner bash
    if ! flock -s -w "${SC_ACME_SNAPSHOT_WAIT:-60}" "$lock" bash -c 'cp -f "$1" "$2" && sha256sum < "$3" > "$4"' \
        _ "$named/acme-zones.json" "$dir/manifest.snapshot.json" "$conf" "$dir/manifest.live.sha256"
    then
        rm -f "$dir/manifest.snapshot.json" "$dir/manifest.live.sha256"
        err "DNS-01: could not snapshot the zone manifest; no DNS-01 issuance this run"
    fi
    return 0
}

## regenerate_letsencrypt: regenerate_certificates hook payload. Tries to
## make sure acme-server.service is running, prepares $SC_DATASTORE_DIR/cert
## and /etc/letsencrypt/live, snapshots the DNS-01 zone manifest, then runs
## letsencrypt.js (letsencrypt_main, bashlib.sh). When acme-server cannot be
## started only http-01 is unavailable: DNS-01 issuance, wildcard
## distribution and the handover state machine still run.
function regenerate_letsencrypt {
    local http01=true

    if [[ "$(systemctl is-active acme-server.service)" != "active" ]]
    then
        run systemctl enable acme-server.service
        run systemctl start acme-server.service
        run systemctl status acme-server.service --no-pager
    fi

    if [[ "$(systemctl is-active acme-server.service)" != "active" ]]
    then
        err "Acme server is not running! http-01 issuance is unavailable this run."
        systemctl status acme-server.service --no-pager
        http01=false
    fi

    mkdir -p "$SC_DATASTORE_DIR/cert"
    mkdir -p /etc/letsencrypt/live

    acme_snapshot_manifest

    msg "Regenerate letsencrypt certificates"
    local -x SC_ACME_COMMAND="$CMD"
    local -x SC_ACME_HTTP01_AVAILABLE="$http01"
    local -x SC_ACME_HTTP01_FALLBACK="${SC_ACME_HTTP01_FALLBACK:-false}"
    ## /etc/srvctl/*.conf is sourced, not exported: hand the other operator
    ## knobs to the node process only when they are set
    local knob
    for knob in SC_ACME_MAX_ISSUE_PER_RUN SC_ACME_DNS01_ONLY SC_LETSENCRYPT_STAGING SC_WILDCARD_EXCLUDE
    do
        [[ -n "${!knob:-}" ]] && export "${knob?}"
    done
    letsencrypt_main
}
