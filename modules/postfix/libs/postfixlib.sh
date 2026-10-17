#!/bin/bash

##
##   modules/postfix/libs/postfixlib.sh — postfix config writers.
##
##   Sourced via load_libs when SC_USE_POSTFIX=true (farm hosts only).
##   Cross-module ABI: write_ve_postfix_conf is called from the containers
##   module at add-ve time (modules/containers/libs/addcontainerlib.sh) —
##   do not rename it. The ve-main.cf template installed here is also
##   written directly by the base-image builder
##   (modules/containers/libs/mkrootfs_fedora.sh).
##

## regenerate_etc_postfix_relaydomains
## Rewrite the host relay map /etc/postfix/relaydomains from the datastore
## ('get cluster postfix_relaydomains': one "<domain><TAB>OK" line per
## host, container — 'mail.' prefix stripped — and container alias) and
## postmap it. No-op when /etc/postfix/ does not exist. Only caller:
## hooks/regenerate.sh.
function regenerate_etc_postfix_relaydomains() {
    if [[ -d /etc/postfix/ ]]
    then
        get cluster postfix_relaydomains > /etc/postfix/relaydomains
        postmap /etc/postfix/relaydomains
    fi
}

## write_ve_postfix_conf <container>
## Write the container main.cf for a container AND its mail-pair twin:
## for "mail.X" also X, for "X" also "mail.X" (the pair test is the
## literal 5-character "mail." prefix). Missing twins are skipped
## silently by write_ve_postfix_main.
function write_ve_postfix_conf { #container
    local container
    container="$1"

    if [[ "${container:0:5}" == "mail." ]]
    then
        msg "write postfix for mail container"
        write_ve_postfix_main "${container:5}"
        write_ve_postfix_main "$container"
    else
        msg "write postfix for container"
        write_ve_postfix_main "$container"
        write_ve_postfix_main "mail.$container"
    fi
}


## write_ve_postfix_main <container>
## Install conf/ve-main.cf (relayhost = srvctl-gateway, Maildir delivery)
## as /srv/<container>/rootfs/etc/postfix/main.cf. Returns 0 silently if
## the container directory or its rootfs/etc/postfix is missing; errors
## if the datastore does not know the container. The previous main.cf is
## appended to a timestamped main.cf-$NOW.bak first.
function write_ve_postfix_main { #container
    local container conf
    container="$1"

    if [[ ! -d /srv/$container ]]
    then
        return 0
    fi

    if [[ ! -d /srv/$container/rootfs/etc/postfix ]]
    then
        return 0
    fi

    if [[ $(get container "$container" exist) == true ]]
    then
        msg "Writing postfix configuration for $container"

        conf="/srv/$container/rootfs/etc/postfix/main.cf"

        if [[ ! -f $conf ]]
        then
            err "$conf does not exist"
        else
            cat "$conf" >> "/srv/$container/rootfs/etc/postfix/main.cf-$NOW.bak"
        fi

        cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-main.cf" > "$conf"
    else
        err "$container dont exists"
    fi
}

## write_postfix_main
## Rewrite the local /etc/postfix/main.cf from conf/ve-main.cf and restart
## postfix — intended to run inside a container.
## FIXME(v4): low — dead code, no callers anywhere in the tree, and the
## in-container use is unreachable because the module condition is always
## false inside nspawn containers (containers/module-condition.sh).
function write_postfix_main {
    local container conf

    container="$HOSTNAME"
    conf="/etc/postfix/main.cf"

    msg "Writing postfix configuration in $container "

    if [[ ! -f $conf ]]
    then
        err "$conf does not exist"
    else
        cat "$conf" >> "/etc/postfix/main.cf-$NOW.bak"
    fi

    cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-main.cf" > "$conf"

    run systemctl restart postfix
}

## regenerate_reinjection_milters [postfix config dir, default /etc/postfix]
## The amavis reinjection listener (*:10025) must not run OpenDKIM: its client
## is 127.0.0.1, an opendkim InternalHost, so it signed inbound mail, including
## a spoofed "From: <one of our domains>" from the internet. Outgoing mail is
## signed on the first pass (container, SMTP AUTH and local clients). Hosts
## only run regenerate, so the one master.cf override is set in place
## (conf/hs-master.cf has it for update-install). An override without the
## opendkim socket or a $parameter (empty, or another milter) stays.
function regenerate_reinjection_milters() {
    local dir="${1:-/etc/postfix}" svc value found=false
    [[ -f $dir/master.cf ]] || return 0
    for svc in $(postconf -c "$dir" -M 2> /dev/null | awk '$2 == "inet" && $1 ~ /:10025$/ { print $1 }')
    do
        found=true
        value="$(postconf -c "$dir" -P 2> /dev/null | awk -v k="$svc/inet/smtpd_milters" '$1 == k { sub(/^[^=]*= ?/, ""); print "set:" $0 }')"
        [[ $value == set:* && $value != *:8891* && $value != *\$* ]] && continue
        postconf -c "$dir" -P "$svc/inet/smtpd_milters=" && msg "postfix: no milters on the $svc reinjection (inbound mail is not DKIM-signed)"
    done
    $found || err "postfix: no *:10025 reinjection listener in $dir/master.cf; DKIM signing of inbound mail not checked"
    return 0
}

## regenerate_smtp_auth [postfix config dir, default /etc/postfix]
## SMTP AUTH checks passwords through saslauthd -> rimap -> perdition's IMAP
## on 127.0.0.1:143 (saslauthd module). perdition is no longer installable, so
## where it is missing no login can succeed and the smtps listener only serves
## password sprayers (r2: 0 logins in 60 days). There SMTP AUTH is turned off:
## the smtps service is removed from master.cf and smtpd_sasl_auth_enable = no.
## A host that still has perdition keeps its AUTH. Only ever turns AUTH off.
function regenerate_smtp_auth() {
    local dir="${1:-/etc/postfix}"
    [[ -f $dir/master.cf ]] || return 0
    [[ -x ${SC_SMTP_AUTH_BACKEND:-/usr/sbin/perdition.imap4} ]] && return 0
    if [[ -n $(postconf -c "$dir" -M smtps/inet 2> /dev/null) ]]
    then
        postconf -c "$dir" -MX smtps/inet && msg "postfix: smtps (465) removed, no SMTP AUTH backend (perdition)"
    fi
    if [[ $(postconf -c "$dir" -h smtpd_sasl_auth_enable 2> /dev/null) != no ]]
    then
        postconf -c "$dir" -e 'smtpd_sasl_auth_enable = no' && msg "postfix: SMTP AUTH off, no backend (perdition)"
    fi
    return 0
}
