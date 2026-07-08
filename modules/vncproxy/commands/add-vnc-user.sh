#!/bin/bash

## @@@ add-vnc-user VE USERNAME
## @en Add user to the vnc server
## &en Create the user for remote vnc access.
## &en use name, email, phone number

hs_only

## Register a VNC user for a container and regenerate the proxy routing:
## - stores the (lowercased) username in the datastore
##   (containers.json -> containers[VE].vncusers array)
## - vncproxycfg (libs/bashlib.sh) reruns vncproxy.js, which rewrites
##   /var/vncproxy/records for ALL containers and prints the derived
##   password — the only time it is ever shown
## - restarts the vncproxy service so the new forward key becomes active
## The exit code of the final systemctl status is the command's exit code.

C="$ARG"
username="${OPA,,}"

## WP-E.2.b: register a vnc user is owner-scoped (root or the container owner);
## check BEFORE the datastore write. Closes the old "no privilege check" gap.
owner_only container "$C"

## FIXME(v4): regex is unanchored, so any string containing a single
## lowercase letter passes; the raw value is stored in the datastore and
## ends up in /var/vncproxy/records, which start.sh sources as root bash
## and splices into an unquoted sqlite INSERT — injection surface.
if ! [[ "$username" =~ (([a-z]|[a-z_][a-z0-9_]{2,30})) ]]
then
    err "Invalid username: $username"
    exit 22
fi

add container "$C" vncuser "$username"

mkdir -p /var/vncproxy

vncproxycfg "$C" "$username"

## opening the firewall for the vnc port is a manual step:
#run firewall-cmd --add-service=vnc-server --permanent
#run firewall-cmd --reload

systemctl restart vncproxy
systemctl status vncproxy  --no-pager -n 30
