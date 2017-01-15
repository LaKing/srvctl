#!/bin/bash


if [[ -d /etc/srvctl/data ]]
then
    msg "Found /etc/srvctl/data dir."
else
    msg "/etc/srvctl/data directory not found. It is recommended to have such a folder prepared."
    msg "Creating Empty database."
fi

init_datastore

if [[ ! -f /etc/srvctl/host.conf ]]
then
    msg "Writing host.conf based on hosts.json"
    out host "$HOSTNAME"
    exif
    out host "$HOSTNAME" > /etc/srvctl/host.conf
    source /etc/srvctl/host.conf
fi

