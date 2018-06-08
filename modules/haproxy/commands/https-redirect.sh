#!/bin/bash

## @@@ https-redirect VE [none|http|URL]
## @en Redirect https traffic of a given VE to a given URL or protocol
## &en Place a redirect rule on the VE within the proxy configuration. IPv4 only, on the default port.
## &en The URL should contain the protocol and/or the domain name.
## &en If neither a keyword nor an URL is given the redirect is removed.
## &en If the keyword is 'none' the redirect is removed as well.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container
#authorize
container_user="$(get container "$ARG" user)"
exif
container_reseller="$(get container "$ARG" reseller)"
exif
msg "Container $ARG - $container_user ($container_reseller) - $OPA"

if [[ $SC_USER == $container_user ]] || [[ $SC_USER == $container_reseller ]]
then
    sudomize
fi

if [[ $USER == root ]]
then
    put container "$ARG" https-redirect "$OPA"
    run_hook regenerate_certificates
    regenerate_haproxy_conf
else
    err "$SC_USER has no access to $ARG"
    exit
fi

## this is actually a setting for all reverse proxies
