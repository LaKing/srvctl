#!/bin/bash

## @@@ http-redirect VE [none|https|URL]
## @en Redirect http traffic of a given VE to a given URL or protocol
## &en Place a redirect rule on the VE within the proxy configuration. IPv4 only, on the default port.
## &en The URL should contain the protocol and/or the domain name.
## &en If neither a keyword nor an URL is given the redirect is removed.
## &en If the keyword is 'none' the redirect is removed as well.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   haproxy/commands/http-redirect.sh — set/clear the http redirect rule
##   of a container in the datastore, then re-render the proxy.
##
##   Stores $OPA under the container key 'http-redirect' (empty/'none'
##   removes the key), refreshes certificates via the
##   regenerate_certificates hook, and regenerates+reloads haproxy.
##   Key semantics in haproxy.js: absent key = default 301 http->https;
##   'none' = serve http directly; 'https' = protocol flip; any other
##   value is used verbatim as 'redirect prefix <value>'.
##
##   Owner/reseller callers are escalated via sudomize (which re-executes
##   as root and exits); twin of https-redirect.sh differing only in the
##   datastore key.
##

argument container
C="$ARG"
#authorize
container_user="$(get container "$C" user)"
exif
container_reseller="$(get container "$C" reseller)"
exif
msg "Container $ARG - $container_user ($container_reseller) - $OPA"

## the container owner and its reseller may act as root
if [[ $SC_USER == "$container_user" ]] || [[ $SC_USER == "$container_reseller" ]]
then
    sudomize
fi

## Owner/reseller escalated via sudomize above; a non-owner non-root caller
## reaches the deny branch below (WP-E.1: was the always-true '[[ $SC_UID0 ]]').
if $SC_UID0
then
    put container "$C" http-redirect "$OPA"
    run_hook regenerate_certificates
    regenerate_haproxy_conf
else
    err "$SC_USER has no access to $C"
    exit 44
fi

## this is actually a setting for all reverse proxies
