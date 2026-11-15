#!/bin/bash

##
##   certificates/libs/prunelib.sh — remove certificates nothing serves.
##
##   $SC_DATASTORE_DIR/cert holds one NAME.pem per served name: container
##   names (the self-signed certificate of add-ve, the wildcard copies of
##   wildcardcertlib.sh) and every domain of a container (letsencrypt). haproxy
##   loads the whole directory, so a certificate of a removed container or a
##   removed alias stays loaded for good. cert/wildcard-retired is where
##   acmerun.js moves a wildcard certificate that left DNS-01; nothing reads
##   it, and an expired one is of no use to the operator either.
##
##   cert/wildcard is managed by acmerun.js (it retires what is not served)
##   and is not touched here.
##

function prune_certificates {
    local dir="$SC_DATASTORE_DIR/cert" rows C domains file name wanted

    [[ -n ${SC_PRUNE_CONTAINERS:-} ]] || return 0

    ## One row per container: its name and the JSON list of its domains.
    rows="$(list container domains)" || return 0
    wanted=" $HOSTNAME "
    while IFS=$'\t' read -r C domains
    do
        [[ -n $C ]] || continue
        ## '-' is a list that could not be derived: the set would be incomplete
        if [[ $domains != \[*\] ]]
        then
            err "The domains of $C are unknown, no certificate is removed"
            return 0
        fi
        domains="${domains//[\[\]\"]/}"
        wanted+="$C ${domains//,/ } "
    done <<< "$rows"

    for file in "$dir"/*.pem
    do
        [[ -f $file ]] || continue
        name="${file##*/}"
        name="${name%.pem}"
        [[ $wanted != *" $name "* ]] || continue
        container_is_gone "$name" || continue
        prune "$file"
    done

    for file in "$dir"/wildcard-retired/*.pem
    do
        [[ -f $file ]] || continue
        ## -checkend 0 fails for a certificate that is no longer valid
        if ! openssl x509 -in "$file" -noout > /dev/null 2>&1 || openssl x509 -in "$file" -noout -checkend 0 > /dev/null 2>&1
        then
            continue
        fi
        prune "$file"
    done
}
