#!/bin/bash

##
##   containers/libs/domainonlylib.sh — domain-only records and retire-ve.
##
##   A domain-only record is a container record with the field
##   domain_only=true: the container's files (rootfs, nspawn files, /srv/C) are
##   gone, the record stays because the domain still lives through it — the DNS
##   zone (named), the haproxy routing to its web_ve, relaydomains and the
##   mail_ve routing, the certificate and the DKIM signing. retire-ve makes one
##   out of a container. Regenerate, prune and the container commands skip or
##   refuse such a record; remove-ve / destroy-ve delete it as any record.
##
##   The DKIM private key of a domain-only record lives host-side in
##   $SC_DATASTORE_DIR/opendkim/<domain>/<selector>.private (the folder
##   opendkim.js writes and opendkimlib.sh mirrors to /var/opendkim);
##   opendkim.js never generates a replacement key for it.
##

## run only with srvctl
[[ $SRVCTL ]] || exit 4

## TEST SEAM for the selftest, not supported configuration.
: "${SC_RETIRE_SRV_DIR:=/srv}"

## True when C is a domain-only record. One datastore read; loops use list.
function container_is_domain_only { ## C
    [[ $(get container "$1" domain_only 2> /dev/null) == true ]]
}

## For commands (|| exit 22) and the low-level writers (|| return 1).
function not_domain_only { ## C [WHAT]
    container_is_domain_only "$1" || return 0
    err "$1 is a domain-only record (retired with retire-ve): ${2:-this} is not possible"
    return 1
}

## The names of every domain-only record, one per line, from one datastore
## read. Prints nothing when the read fails.
function domain_only_containers {
    local C value
    while IFS=$'\t' read -r C value
    do
        [[ $value == true ]] && echo "$C"
    done < <(list container domain_only 2> /dev/null)
    return 0
}

## The DKIM selector, as entitlement.selector in modules/opendkim/lib/entitlement.js.
function dkim_selector { ## domain
    if [[ $1 == mail.* ]]
    then
        echo mail
    else
        echo default
    fi
}

## Copy the DKIM key of C from SRC (the container's opendkim directory) to
## DEST/C (the host-side copy opendkim.js signs with) and verify the copy.
## Returns non-zero when a key exists and could not be preserved.
function preserve_dkim_keys { ## C SRC DEST
    local C="$1" src="$2" dest="$3/$1" sel file
    sel="$(dkim_selector "$C")"

    if [[ -f $src/$sel.private ]]
    then
        mkdir -p "$dest" || return 1
        for file in "$sel.private" "$sel.txt"
        do
            [[ -f $src/$file ]] || continue
            cp -p "$src/$file" "$dest/$file" || return 1
            cmp -s "$src/$file" "$dest/$file" || return 1
        done
        msg "DKIM key of $C preserved in $dest"
        return 0
    fi

    if [[ -f $dest/$sel.private ]]
    then
        ntc "DKIM key of $C kept from $dest/$sel.private"
        return 0
    fi

    ntc "$C has no DKIM key: mail from $C will not be signed"
    return 0
}

## Refuse what retire-ve must not do; changes nothing. OPA is the third word
## of the command line: empty, or no-web.
function retire_ve_preflight { ## C OPA
    local C="$1" opa="$2" web mail bridge host other ow om

    if [[ -n $opa && $opa != no-web ]]
    then
        err "Unknown option: $opa (the only option is no-web)"
        return 1
    fi
    if container_is_domain_only "$C"
    then
        err "$C is a domain-only record already"
        return 1
    fi
    if [[ ! -d $SC_RETIRE_SRV_DIR/$C/rootfs ]]
    then
        err "$C has no rootfs on $HOSTNAME: run retire-ve on the host that holds the container"
        return 1
    fi

    ## Without a rootfs the owner is derived from the ip (datastore derive.mjs,
    ## container_host). Retire only when that is this host, as the other hosts
    ## already see it; a bridge container has no owner in its ip.
    bridge="$(get container "$C" bridge 2> /dev/null)"
    if [[ -n $bridge && $bridge != false ]]
    then
        err "$C uses the bridge $bridge: its host cannot be derived without the rootfs, not retired"
        return 1
    fi
    host="$(get container "$C" host_by_ip 2> /dev/null)"
    if [[ $host != "$HOSTNAME" ]]
    then
        err "The ip of $C belongs to the network of ${host:-no host}, not $HOSTNAME: retiring it would move the record's owner, not retired"
        return 1
    fi

    web="$(get container "$C" web_ve 2> /dev/null)"
    if [[ -z $web ]]
    then
        if [[ $opa != no-web ]]
        then
            err "$C has no web_ve: hand its web to another VE first (set-ve-web-ve $C WEBVE), or accept a domain without web: retire-ve $C no-web"
            return 1
        fi
        ntc "$C is retired without web (no-web)"
    elif [[ $web == "$C" ]] || [[ $(get container "$web" exist 2> /dev/null) != true ]] || container_is_domain_only "$web"
    then
        err "The web_ve of $C, $web, is not an existing container"
        return 1
    fi

    mail="$(get container "$C" mail_ve 2> /dev/null)"
    if [[ -z $mail ]]
    then
        err "MAIL: $C has no mail_ve. Mail for $C keeps being relayed to its ip, where no container answers. Set one with set-ve-mail-ve $C MAILVE"
    elif [[ $mail == "$C" ]] || [[ $(get container "$mail" exist 2> /dev/null) != true ]] || container_is_domain_only "$mail"
    then
        err "The mail_ve of $C, $mail, is not an existing container"
        return 1
    fi

    while IFS=$'\t' read -r other ow om
    do
        [[ $other != "$C" ]] || continue
        if [[ $ow == "$C" || $om == "$C" ]]
        then
            err "$other hands its web or mail to $C: move it first (set-ve-web-ve / set-ve-mail-ve)"
            return 1
        fi
    done < <(list container web_ve mail_ve)

    return 0
}

## Make C a domain-only record. The caller ran retire_ve_preflight.
##
## Order: backup and the DKIM key first, so a failure there leaves everything
## as it was. Then the record is marked before the files go: a run that dies
## after that leaves a domain-only record with a leftover /srv/C, which every
## regenerate path ignores. The other order would leave a record without files,
## which check_container_database rebuilds as a fresh container.
function retire_ve { ## C
    local C="$1"

    msg "Retire container $C of $(get container "$C" user)"

    backup_ve "$C"

    if ! preserve_dkim_keys "$C" "$SC_RETIRE_SRV_DIR/$C/opendkim" "$SC_DATASTORE_DIR/opendkim"
    then
        err "$C: the DKIM key could not be copied to $SC_DATASTORE_DIR/opendkim/$C, nothing is deleted"
        exit 1
    fi

    put container "$C" domain_only true

    ## off the boot target, and masked: nothing may start it again
    rm -f "/etc/systemd/system/machines.target.wants/srvctl-nspawn@$C.service"
    rm -f "$(container_limits_dropin "$C")"
    run systemctl mask "srvctl-nspawn@$C.service"

    if ! remove_container_tree "$C" "$SC_RETIRE_SRV_DIR/$C"
    then
        err "$C is a domain-only record now, but its files in /srv/$C are not removed. Unmount everything listed above, check that 'findmnt -R /srv/$C' lists nothing, then finish with: sc exec-function remove_container_tree $C /srv/$C"
        exit 16
    fi

    ## the forwarded ports led to the container; prune closes them
    if [[ -n $(get container "$C" mapped_ports 2> /dev/null) ]]
    then
        put container "$C" mapped_ports
    fi

    ## unit drop-ins, comount units, the codepad share and the users' shares
    run_prune

    msg "$C retired: the domain-only record keeps its zone, routing, certificate and DKIM key (web: $(get container "$C" web_ve 2> /dev/null || echo none), mail: $(get container "$C" mail_ve 2> /dev/null || echo none))"
    ntc "Check it with: sc regenerate"
}
