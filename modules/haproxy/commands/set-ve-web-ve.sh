#!/bin/bash

## @@@ set-ve-web-ve VE [WEBVE|off]
## @en Hand the web traffic of a VE to another VE, WEBVE: it serves http and https for the VE's names
## &en HAProxy sends http/https of the VE, its www. variant, aliases and subdomains to WEBVE, Host header unchanged.
## &en WEBVE's web server needs a virtual host for those names; redirects, basic auth and certificates stay the VE's.
## &en Without WEBVE the current setting is shown. 'off' or 'none' gives the web traffic back to the VE.
## &en Other proxied ports (codepad, 8080, 8443, 9200) and the mail stay with the VE.

root_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   haproxy/commands/set-ve-web-ve.sh — set/clear the container field web_ve.
##
##   Consumer: web_ve() in haproxy.js, which rewrites only the server line of
##   the http:VE and https:VE backends. A target that itself hands its web
##   traffic on is refused: haproxy.js follows one step only.
##

argument container
C="$ARG"
[[ $(get container "$C" exist) == true ]] || { err "No such container: $C"; exit 22; }

if [[ -z $OPA ]]
then
    msg "Web of $C is served by $(get container "$C" web_ve || echo "$C itself")"
    exit 0
fi

if [[ $OPA == off || $OPA == none ]]
then
    put container "$C" web_ve > /dev/null
    regenerate_haproxy_conf
    msg "Web of $C is served by $C again"
    exit 0
fi

target="$OPA"
[[ $target != "$C" ]] || { err "A VE cannot hand its web traffic to itself; use off"; exit 22; }
[[ $(get container "$target" exist) == true ]] || { err "No such container: $target"; exit 22; }
[[ -z $(get container "$target" web_ve) ]] || { err "$target hands its own web traffic on; chains are not followed"; exit 22; }

put container "$C" web_ve "$target" > /dev/null
regenerate_haproxy_conf
msg "Web of $C is served by $target"
ntc "$target needs a virtual host for $C and www.$C; check it with curl -I https://$C"
