#! /bin/bash

if [[ $HOSTNAME == localhost.localdomain ]]
then
    echo false
    return
fi

readonly SC_VIRT=$(systemd-detect-virt -c)

## lxc is deprecated, but we can consider it a container ofc.
if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
then
    echo true
    return
fi


if [[ $SC_HOSTNET ]] || [[ -d /etc/srvctl/data ]]
then
    
    if [[ -f /etc/srvctl/hosts.json ]] && grep --quiet "\"$HOSTNAME\"" /etc/srvctl/hosts.json
    then
        echo true
        return
    fi
fi

if [[ $CMD == update-install ]] && [[ $ARG ]]
then
    echo true
    return
fi

echo false
