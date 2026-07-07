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

## WP-E.2: root passes, owner/reseller escalates, else denied — before the
## write. Now shares owner_only with its twin http-redirect (was a divergent
## '[[ $USER == root ]]' gate).
owner_only container "$ARG"

put container "$ARG" https-redirect "$OPA"
run_hook regenerate_certificates
regenerate_haproxy_conf

## this is actually a setting for all reverse proxies
