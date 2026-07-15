#!/bin/bash

##
##   certificates/libs/certselectlib.sh — choose + sync the certs haproxy serves.
##
##   sync_haproxy_certificates rebuilds the haproxy cert directory (default
##   /var/haproxy) as the DESIRED set and PRUNES everything else, so a renewed
##   or better cert can never be shadowed by a stale copy (the old
##   load_certificate_folder_files used `cp -u` and never pruned — the cause of
##   an expired wildcard continuing to be served after a renewal).
##
##   Preference, per served domain:
##     1. a matching WILDCARD cert  (admin certs in /etc/srvctl/cert/<d>/*.pem)
##     2. a per-domain cert         (letsencrypt / CA-signed, in the datastore
##                                   cert dir), i.e. anything not wildcard-covered
##     3. (self-signed per-container certs live in /srv/<c>/cert and are not
##        served by haproxy, so they never reach this directory)
##   A valid (unexpired) cert always beats an expired one; among candidates for
##   the same target the later notAfter wins. Because haproxy SNI prefers an
##   EXACT per-domain match over a wildcard, a domain covered by a valid wildcard
##   gets NO per-domain file here — the wildcard serves it.
##
##   Dirs are overridable for testing:
##     SC_ADMIN_CERT_DIR (default /etc/srvctl/cert), $SC_DATASTORE_DIR/cert,
##     and the target dir (arg 1, default /var/haproxy).

[[ $SRVCTL ]] || exit 10

## cert_notafter_epoch PEM: echo the leaf cert's notAfter as epoch seconds.
function cert_notafter_epoch {
    local end
    end="$(openssl x509 -enddate -noout -in "$1" 2> /dev/null | cut -d= -f2)"
    [[ -n "$end" ]] || return 1
    date -d "$end" +%s 2> /dev/null
}

## cert_valid PEM: 0 if the leaf certificate is not expired (checkend 0).
function cert_valid {
    openssl x509 -checkend 0 -noout -in "$1" > /dev/null 2>&1
}

## cert_newer A B: 0 if cert A's notAfter is >= cert B's (A at least as fresh).
## True when B is missing/unreadable so a first candidate always wins.
function cert_newer {
    local a b
    a="$(cert_notafter_epoch "$1")" || return 1
    b="$(cert_notafter_epoch "$2")" || return 0
    [[ "$a" -ge "$b" ]]
}

## domain_under_wildcard DOMAIN BASE: 0 if a *.BASE cert covers DOMAIN — either
## DOMAIN == BASE, or DOMAIN == <single-label>.BASE (wildcards match one level).
function domain_under_wildcard {
    local domain base head
    domain="$1"; base="$2"
    [[ "$domain" == "$base" ]] && return 0
    [[ "$domain" == *".$base" ]] || return 1
    head="${domain%".$base"}"
    [[ "$head" != *"."* ]]
}

## sync_haproxy_certificates [TARGET_DIR]: build the served cert set + prune.
function sync_haproxy_certificates {
    local hadir admindir dsdir src base d bn b covered
    hadir="${1:-/var/haproxy}"
    admindir="${SC_ADMIN_CERT_DIR:-/etc/srvctl/cert}"
    dsdir="$SC_DATASTORE_DIR/cert"
    mkdir -p "$hadir"

    local -A desired=()
    local wildcard_bases=""

    ## 1) admin WILDCARD certs (highest priority). Newer wins per base domain.
    for src in "$admindir"/*/*.pem
    do
        [[ -f "$src" ]] || continue
        base="$(check_wildcard_pem "$src")"           ## base domain, or "false"
        [[ "$base" == false ]] && continue
        bn="$base.pem"
        if [[ -z "${desired[$bn]:-}" ]] || cert_newer "$src" "$hadir/$bn"
        then
            install -m 600 "$src" "$hadir/$bn"
            desired["$bn"]=1
        fi
        case " $wildcard_bases " in *" $base "*) ;; *) wildcard_bases+=" $base" ;; esac
    done

    ## 2) per-domain certs (letsencrypt / fanned). Skip any domain a valid
    ##    wildcard already covers (wildcard preferred). Skip expired. Newer wins.
    for src in "$dsdir"/*.pem
    do
        [[ -f "$src" ]] || continue
        d="$(basename "$src" .pem)"
        cert_valid "$src" || continue
        covered=false
        for b in $wildcard_bases
        do
            if domain_under_wildcard "$d" "$b"; then covered=true; break; fi
        done
        $covered && continue
        bn="$d.pem"
        if [[ -z "${desired[$bn]:-}" ]] || cert_newer "$src" "$hadir/$bn"
        then
            install -m 600 "$src" "$hadir/$bn"
            desired["$bn"]=1
        fi
    done

    ## 3) PRUNE: remove stale shadows, superseded per-domain copies of now
    ##    wildcard-covered domains, expired leftovers, and the non-servable CA
    ##    bundle — anything not in the desired set just built.
    for src in "$hadir"/*.pem
    do
        [[ -f "$src" ]] || continue
        bn="$(basename "$src")"
        if [[ "$bn" == ca-bundle.pem ]] || [[ -z "${desired[$bn]:-}" ]]
        then
            rm -f "$src"
        fi
    done
}
