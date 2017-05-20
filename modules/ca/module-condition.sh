#! /bin/bash
[[ -f /etc/srvctl/data/ca.conf ]] && source /etc/srvctl/data/ca.conf
[[ -f /etc/srvctl/ca.conf ]] && source /etc/srvctl/ca.conf

if [[ $SC_ROOTCA_HOST == "$HOSTNAME" ]]
then
    echo true
    return
fi

echo false
