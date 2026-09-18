#!/bin/bash

##
##   certificates/libs/wildcardgatelib.sh — the one wildcard-validity rule.
##
##   Shared by certselect (what haproxy serves), the wildcard fan-out and the
##   letsencrypt http-01 gate (modules/letsencrypt/acmeplan.js), so "a
##   wildcard suppresses http-01 for a name" and "haproxy serves a wildcard
##   for that name" can never disagree.
##
##   Self-contained on purpose: no SRVCTL guard, no lablib helpers (msg, err,
##   debug ...), nothing executed at source time, only bash builtins,
##   openssl, date and basename. load_libs sources it together with the other
##   certificates libs (in glob order it comes last; the order is irrelevant
##   because nothing here or in the callers runs at load time), and the node
##   side sources it directly in a bare `bash --noprofile --norc`.
##
##   Two sources of wildcard certificates:
##     admin    ${SC_ADMIN_CERT_DIR:-/etc/srvctl/cert}/<d>/<d>.pem, judged by
##              check_wildcard_pem (unchanged rule: CN *.X, 7 days left)
##     managed  $SC_DATASTORE_DIR/cert/wildcard/<base>.pem, DNS-01 wildcards
##              issued on the DNS primary, judged by wildcard_servable_managed
##

## check_wildcard_pem PEM: echo the wildcard base domain when the pem's
## first certificate is unexpired (7-day checkend) and its subject is a
## wildcard CN; otherwise echo the literal string "false". The echoed
## string is the protocol — callers compare against "false".
## Both subject spellings must stay supported:
## "subject=CN = *.X" (OpenSSL 1.x) and "subject=CN=*.X" (OpenSSL 3.x).
function check_wildcard_pem { ## file
    ## first certificate in pem file must be the certificate.
    
    local pem subject
    pem="$1"
    
    ## check if we have a valid argument
    if [[ -f "$pem" ]]
    then
        ## check if the certificate is not expired
        if openssl x509 -checkend 604800 -noout -in "$pem" > /dev/null
        then
            ## check if it is a wildcard certificate
            subject="$(openssl x509 -in "$pem" -noout --subject)"
            if [[ $subject == "subject=CN = *."* ]]
            then
                ## return the domain of the wildcard certificate
                echo "${subject:15}"
                return
            elif [[ $subject == "subject=CN=*."* ]]
            then
                ## OpenSSL 3.x format without spaces
                echo "${subject:13}"
                return
            fi
        fi
    fi
    
    echo false
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

## wildcard_servable_managed PEM: echo the base domain when PEM is a managed
## DNS-01 wildcard bundle haproxy may serve, otherwise echo "false". Servable
## means: the leaf parses, the bundle's private key matches it, its SAN holds
## both BASE and *.BASE where BASE is the file name without .pem, it is
## already valid (notBefore in the past) and stays valid for at least one
## more day (checkend 86400).
function wildcard_servable_managed { ## pem
    local pem base san start now leafkey pkey
    pem="$1"
    base="${pem##*/}"
    base="${base%.pem}"

    if [[ -f "$pem" ]] && [[ "$base" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] && \
        openssl x509 -checkend 86400 -noout -in "$pem" > /dev/null 2>&1
    then
        start="$(openssl x509 -startdate -noout -in "$pem" 2> /dev/null)"
        start="$(date -d "${start#notBefore=}" +%s 2> /dev/null)"
        now="$(date +%s)"
        leafkey="$(openssl x509 -pubkey -noout -in "$pem" 2> /dev/null)"
        pkey="$(openssl pkey -pubout -in "$pem" 2> /dev/null)"
        san="$(openssl x509 -noout -ext subjectAltName -in "$pem" 2> /dev/null)"
        san=" ${san//,/ } "
        san="${san//$'\n'/ }"
        if [[ -n "$start" ]] && (( start <= now )) && \
            [[ -n "$leafkey" ]] && [[ "$leafkey" == "$pkey" ]] && \
            [[ "$san" == *" DNS:$base "* ]] && [[ "$san" == *" DNS:*.$base "* ]]
        then
            echo "$base"
            return
        fi
    fi

    echo false
}

## wildcard_servable_pairs: print "<base><TAB><file>" for every servable
## wildcard, admin ones first. SC_WILDCARD_EXCLUDE names one file to leave
## out (used when asking whether something other than a given wildcard
## covers a name). The managed source is skipped when SC_DATASTORE_DIR is
## unset, so the function is safe under `set -u`.
function wildcard_servable_pairs {
    local src base exclude
    exclude="${SC_WILDCARD_EXCLUDE:-}"

    for src in "${SC_ADMIN_CERT_DIR:-/etc/srvctl/cert}"/*/*.pem
    do
        [[ -f "$src" ]] || continue
        [[ "$src" == "$exclude" ]] && continue
        base="$(check_wildcard_pem "$src")"
        [[ "$base" == false ]] && continue
        printf '%s\t%s\n' "$base" "$src"
    done

    [[ -n "${SC_DATASTORE_DIR:-}" ]] || return 0
    for src in "$SC_DATASTORE_DIR"/cert/wildcard/*.pem
    do
        [[ -f "$src" ]] || continue
        [[ "$src" == "$exclude" ]] && continue
        base="$(wildcard_servable_managed "$src")"
        [[ "$base" == false ]] && continue
        printf '%s\t%s\n' "$base" "$src"
    done
}

## wildcard_covering DOMAIN: exit 0 and print the covering file when a
## servable wildcard covers DOMAIN (domain_under_wildcard), exit 1 otherwise.
function wildcard_covering { ## domain
    local domain base src
    domain="$1"
    while IFS=$'\t' read -r base src
    do
        if domain_under_wildcard "$domain" "$base"
        then
            echo "$src"
            return 0
        fi
    done < <(wildcard_servable_pairs)
    return 1
}

## wildcard_covering_many: read domains (one per line) on stdin and print
## "<domain><TAB><covering file or ->" for each, judging every wildcard file
## only once. Same rule as wildcard_covering, for callers with many names.
function wildcard_covering_many {
    local domain base src found
    local -a bases=() files=()
    local i
    while IFS=$'\t' read -r base src
    do
        bases+=("$base")
        files+=("$src")
    done < <(wildcard_servable_pairs)

    while IFS= read -r domain
    do
        [[ -n "$domain" ]] || continue
        found="-"
        for i in "${!bases[@]}"
        do
            if domain_under_wildcard "$domain" "${bases[$i]}"
            then
                found="${files[$i]}"
                break
            fi
        done
        printf '%s\t%s\n' "$domain" "$found"
    done
}
