#!/bin/bash

## @@@ add-vnc-user VE USERNAME
## @en Add user to the vnc server
## &en Create the user for remote vnc access.
## &en use name, email, phone number

#local
hs_only

C="$ARG"
username="${OPA,,}"

if ! [[ "$username" =~ (([a-z]|[a-z_][a-z0-9_]{2,30})) ]]
then
    err "Invalid username: $username"
    exit 22
fi

add container "$C" vncuser "$username"

mkdir -p /var/vncproxy

vncproxycfg "$C" "$username"

#run firewall-cmd --add-service=vnc-server --permanent
#run firewall-cmd --reload

systemctl restart vncproxy
systemctl status vncproxy  --no-pager -n 30
 