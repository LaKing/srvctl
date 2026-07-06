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

##
##   haproxy/commands/https-redirect.sh — set/clear the https redirect rule
##   of a container in the datastore, then re-render the proxy.
##
##   Stores $OPA under the container key 'https-redirect' (empty/'none'
##   removes the key), refreshes certificates via the
##   regenerate_certificates hook, and regenerates+reloads haproxy.
##   Key semantics in haproxy.js: absent key or 'none' = serve https
##   directly; 'http' = protocol flip; any other value is used verbatim
##   as 'redirect prefix <value>'.
##
##   Owner/reseller callers are escalated via sudomize (which re-executes
##   as root and exits); twin of http-redirect.sh differing only in the
##   datastore key.
##

argument container
#authorize
container_user="$(get container "$ARG" user)"
exif
container_reseller="$(get container "$ARG" reseller)"
exif
msg "Container $ARG - $container_user ($container_reseller) - $OPA"

## the container owner and its reseller may act as root
if [[ $SC_USER == "$container_user" ]] || [[ $SC_USER == "$container_reseller" ]]
then
    sudomize
fi

## FIXME(v4): inconsistent root gate — twin http-redirect.sh tests the
## always-true '[[ $SC_UID0 ]]'; this one checks the ambient $USER instead
## of the srvctl convention '$SC_UID0 == true'. It works, but the pair
## should share one real authorization helper.
if [[ $USER == root ]]
then
    put container "$ARG" https-redirect "$OPA"
    run_hook regenerate_certificates
    regenerate_haproxy_conf
else
    err "$SC_USER has no access to $ARG"
    ## WP-E.1: was a bare exit (status 0). The gate ([[ $USER == root ]]) is
    ## the working twin of http-redirect; unifying the pair on one auth helper
    ## is WP-E.2.
    exit 44
fi

## this is actually a setting for all reverse proxies
