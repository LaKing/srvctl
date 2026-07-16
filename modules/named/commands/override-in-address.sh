#!/bin/bash

## @@@ override-in-address VE [none|ip]
## @en Override the IN A of the container in named DNS server zone file
## &en Temporary redirect the IN A record.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   modules/named/commands/override-in-address.sh — point a container's
##   wildcard/apex A records (and the reverse proxies) at another IP.
##
##   Host-server-only command. Writes the container datastore key
##   override_in_a_ip ("none" clears the override), then runs the ordered
##   all-host regeneration. That rebuilds reverse-proxy and certificate
##   configuration first, publishes the new authoritative zone on the one
##   DNS primary, and finally retransfers and verifies the DNS replicas.
##
##   Authorization is manual here instead of the standard authorize
##   helper: the container's owner or reseller is re-executed via
##   sudomize, then the root check gates the datastore write.
##

argument container
C="$ARG"

## Accept only the sentinel or canonical dotted-decimal IPv4. Anchoring and
## explicit octet bounds keep shell fragments, CIDR suffixes, shorthand forms
## and ambiguous leading-zero representations out of generated BIND zones.
function override_in_address_valid_ipv4() {
    local address="$1" octet
    local -a octets=()

    [[ $address =~ ^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$ ]] || return 1
    IFS=. read -r -a octets <<< "$address"
    for octet in "${octets[@]}"
    do
        (( 10#$octet <= 255 )) || return 1
    done
}

if [[ $OPA != none ]] && ! override_in_address_valid_ipv4 "$OPA"
then
    err "Invalid IN A override: $OPA (expected none or an IPv4 address)"
    exit 22
fi

container_user="$(get container "$C" user)"
exif
container_reseller="$(get container "$C" reseller)"
exif
msg "Container $ARG - $container_user ($container_reseller) - $OPA"

## WP-E.2: root passes, owner/reseller escalates, else denied — before the write.
owner_only container "$C"

put container "$C" override_in_a_ip "$OPA"
exif
regenerate_all_hosts
