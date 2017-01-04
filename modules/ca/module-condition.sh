#! /bin/bash

if [[ -f /etc/srvctl/data/ca.conf ]]
then
    source /etc/srvctl/data/ca.conf
fi

if [[ -f /etc/srvctl/ca.conf ]]
then
    source /etc/srvctl/ca.conf
fi

if [[ $SC_ROOTCA_HOST == "$HOSTNAME" ]]
then
    echo true
    return
fi

echo false
