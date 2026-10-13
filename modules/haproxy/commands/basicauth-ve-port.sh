#!/bin/bash

## @@@ basicauth-ve-port VE [port|off]
## @en Protect a VE with HTTP basic auth in the proxy, using the srvctl user passwords
## &en Without a port every proxied port of the VE asks for a login; with a port only that one.
## &en Ports: 80 443 8080 8443 9000 9001 9002 9200. Repeat the command to add more ports.
## &en Login: every user with access to the VE, with the password in their ~/.password.
## &en 'off' or 'none' removes the protection.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   haproxy/commands/basicauth-ve-port.sh — set/clear basic auth of a container.
##
##   Stores the protected ports under the container key 'basicauth' ("all" or
##   "443,9000"); the key holds no secret. haproxy.js renders the userlist from
##   the access users' datastore .password files via basicauth.js. Users still
##   without a password get one from usersonhost (regenerate_users), the same
##   path that creates it for every user. Ports 80 and 8080 are plain http: a
##   login there sends a host login password in cleartext.
##

argument container
C="$ARG"

## root passes, owner/reseller escalates via sudo, else denied — before the write.
owner_only container "$C"

if [[ $OPA == off || $OPA == none ]]
then
    put container "$C" basicauth
    msg "Basic auth removed from $C"
    regenerate_haproxy_conf
    exit 0
fi

value=all
if [[ -n $OPA ]]
then
    case $OPA in
        80 | 443 | 8080 | 8443 | 9000 | 9001 | 9002 | 9200) ;;
        *)
            err "Port must be one of 80 443 8080 8443 9000 9001 9002 9200"
            exit 32
            ;;
    esac
    current="$(get container "$C" basicauth)"
    if [[ $current == all ]]
    then
        ntc "All ports of $C are protected already"
    elif [[ -n $current ]]
    then
        value="$(tr ',' '\n' <<< "$current,$OPA" | sort -nu | paste -sd,)"
    else
        value="$OPA"
    fi
fi

put container "$C" basicauth "$value"

missing="$(/bin/node "$SC_INSTALL_DIR/modules/haproxy/basicauth.js" missing "$C")"
exif "basicauth: cannot list the users of $C"
if [[ -n $missing ]] && command -v regenerate_users > /dev/null
then
    ntc "Creating the missing passwords: $missing"
    regenerate_users
fi

if [[ $value == all || ,$value, == *,80,* ]] && [[ $(get container "$C" http-redirect) == none ]]
then
    ntc "Port 80 of $C serves plain http: logins there send the password in cleartext"
fi

msg "Basic auth on $C, ports: $value"
regenerate_haproxy_conf
