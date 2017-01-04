#!/bin/bash

sc_install couchdb

run systemctl enable couchdb
run systemctl start couchdb
run systemctl status couchdb --no-pager

## srvctl3 database
mkdir -p /etc/srvctl/data

if ! [[ -f /etc/srvctl/data/hosts.json ]]
then
    echo '{}' > /etc/srvctl/data/hosts.json
fi
if ! [[ -f /etc/srvctl/data/containers.json ]]
then
    echo '{}' > /etc/srvctl/data/containers.json
fi

if ! [[ -f /etc/srvctl/data/resellers.json ]]
then
    echo '{
            "root": {
                "id": 0
            }
    }' > /etc/srvctl/data/resellers.json
fi

if ! [[ -f /etc/srvctl/data/users.json ]]
then
    echo '{
            "root": {
                "uid": 0
            }

    }' > /etc/srvctl/data/users.json
fi

for sourcefile in /etc/srvctl/data/*.conf
do
    [[ -f $sourcefile ]] && cat "$sourcefile" > /etc/srvctl/"${sourcefile:17}"
done
