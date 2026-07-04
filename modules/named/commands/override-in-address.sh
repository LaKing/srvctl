#!/bin/bash

## @@@ override-in-address VE [none|ip]
## @en Override the IN A of the container in named DNS server zone file
## &en Temporary redirect the IN A record.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container
C="$ARG"
#authorize
container_user="$(get container "$C" user)"
exif
container_reseller="$(get container "$C" reseller)"
exif
msg "Container $ARG - $container_user ($container_reseller) - $OPA"

if [[ $SC_USER == "$container_user" ]] || [[ $SC_USER == "$container_reseller" ]]
then
    sudomize
fi

if [[ $SC_UID0 ]]
then
    put container "$C" override_in_a_ip "$OPA"
    run_hook regenerate_certificates
    regenerate_haproxy_conf
else
    err "$SC_USER has no access to $C"
    exit
fi

## this is actually a setting for all reverse proxies
