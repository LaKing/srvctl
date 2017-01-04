#! /bin/bash

if [[ $SC_HOSTNET ]] || [[ -d /etc/srvctl/data ]]
then
    
    readonly SC_VIRT=$(systemd-detect-virt -c)
    
    ## lxc is deprecated, but we can consider it a container ofc.
    if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
    then
        echo false
        return
    fi
    
    echo true
    return
fi


echo false
