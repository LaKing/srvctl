#!/bin/bash

## @@@ set-ve-alias VE ALIAS [off]
## @en Set an ALIAS domain of a VE: it redirects to the VE; without an ALIAS list them
## &en The alias and its www. variant answer with a 301 redirect to the VE's own name, on http and https, path kept.
## &en Certificates are requested for the alias like for the VE; its DNS must point to this host (or be served by our DNS).
## &en Without an ALIAS the aliases are listed. 'off' or 'none' after the ALIAS removes it.
## &en The redirect is cached by browsers for a day: check it with curl -I before announcing it.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/set-ve-alias.sh — add/remove an alias domain of a container.
##
##   The datastore key 'aliases' is an array, so it is written through the
##   cfg functions add_alias/remove_alias (datastore/lib/mutators.mjs), which
##   also refuse a domain used anywhere as a name, alias or altname.
##   Consumers: haproxy.js (redirects), container_domains (certificates),
##   named.js (zone shares the VE's file). This command refreshes them on this
##   host; DNS authorities on other hosts follow at their next regenerate.
##

argument container
C="$ARG"

## root passes, owner/reseller escalates via sudo, else denied — before the write.
owner_only container "$C"

if [[ -z $OPA ]]
then
    ## get prints an array as node's console.log does: [ 'a.hu', 'b.hu' ]
    aliases="$(get container "$C" aliases | tr -d "[]' \n")"
    msg "Aliases of $C: ${aliases:-none}"
    exit 0
fi

domain="${OPA,,}"
if [[ ${SC_ARGV[3]} == off || ${SC_ARGV[3]} == none ]]
then
    cfg container "$C" remove_alias "$domain" > /dev/null
    datastore_push "cfg container $C remove_alias $domain"
    msg "Alias $domain removed from $C"
else
    cfg container "$C" add_alias "$domain" > /dev/null
    datastore_push "cfg container $C add_alias $domain"
    msg "Alias $domain (and www.$domain) redirects to $C"
fi

## DNS first: the http-01 certificate request needs the name to resolve here.
if command -v named_regenerate_activate > /dev/null
then
    named_regenerate_activate
else
    ntc "No DNS server on this host: the DNS authorities pick up $domain at their next regenerate"
fi
run_hook regenerate_certificates
regenerate_haproxy_conf
