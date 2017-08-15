#! /bin/bash

if [[ $HOSTNAME == localhost.localdomain ]]
then
    echo false
    return
fi

if [[ $SC_HOSTNET ]] || [[ -d /etc/srvctl/data ]]
then
    
    readonly SC_VIRT=$(systemd-detect-virt -c)
    
    ## lxc is deprecated, but we can consider it a container ofc.
    if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
    then
        echo false
        return
    fi
    
    if [[ -f /etc/srvctl/hosts.json ]] && grep --quiet "\"$HOSTNAME\"" /etc/srvctl/hosts.json
    then
        echo true
        return
    fi
fi


echo false
