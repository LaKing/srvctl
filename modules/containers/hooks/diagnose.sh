#!/bin/bash

all_containers_pingback

run systemd-cgtop -m -n 1

srv_permissions="$(stat -c "%A" /srv)"
if [[ $srv_permissions == "drwxr-x---" ]]
then
    msg "Permissions on /srv OK"
else
    err "Permissions error on /srv $srv_permissions should be drwxr-x---"
    run getfacl /srv
    #exit
fi