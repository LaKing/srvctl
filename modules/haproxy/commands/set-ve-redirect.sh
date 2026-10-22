#!/bin/bash

## @@@ set-ve-redirect VE [URL [temporary]|off]
## @en Send every request of a VE to one URL, e.g. a Facebook page; 'temporary' makes it a 302
## &en HAProxy answers http and https of the VE and www.VE with a redirect to exactly URL, the path
## &en is not appended. 301 (permanent) by default, 302 with 'temporary'. /.well-known stays with
## &en the VE, so certificates keep renewing. Without URL the current setting is shown; 'off' or
## &en 'none' removes it. Aliases reach URL through their redirect to the VE.

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   haproxy/commands/set-ve-redirect.sh — set/clear the container fields
##   redirect and redirect_code, rendered by siteredirect.js into both
##   haproxy frontends. The URL is validated by the same rule haproxy.js
##   applies, so a stored value never stops the rendering.
##

argument container
C="$ARG"
[[ $(get container "$C" exist) == true ]] || { err "No such container: $C"; exit 22; }

## root passes, owner/reseller escalates, else denied — before the write
owner_only container "$C"

read -ra words <<< "$OPAS"
url="${words[1]:-}"
mode="${words[2]:-}"

if [[ -z $url ]]
then
    current="$(get container "$C" redirect)"
    if [[ -n $current ]]
    then msg "$C redirects to $current (HTTP $(get container "$C" redirect_code || echo 301))"
    else msg "$C has no site redirect"
    fi
    exit 0
fi

if [[ $url == off || $url == none ]]
then
    put container "$C" redirect > /dev/null
    put container "$C" redirect_code > /dev/null
    regenerate_haproxy_conf
    msg "$C serves its own site again"
    exit 0
fi

[[ -z $mode || $mode == temporary ]] || { err "Unknown option: $mode (only 'temporary')"; exit 22; }
/bin/node "$SC_INSTALL_DIR/modules/haproxy/siteredirect.js" "$url" || { err "Not a usable URL: $url (http(s)://host/path, no spaces, quotes or #)"; exit 22; }

put container "$C" redirect "$url" > /dev/null
if [[ $mode == temporary ]]
then put container "$C" redirect_code 302 > /dev/null
else put container "$C" redirect_code > /dev/null
fi
regenerate_haproxy_conf
msg "$C redirects to $url (HTTP $([[ $mode == temporary ]] && echo 302 || echo 301))"
