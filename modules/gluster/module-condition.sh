#! /bin/bash

#source "$SC_INSTALL_DIR/modules/containerfarm/module-condition.sh"

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
        
        ## check if we have servers in this cluster
        ## /{/ {d++} if { is found, increment the depth variable.
        ## /}/ {d--} if } is found, decrement the depth variable.
        ## /{/ && d==1 {count++} if depth is 1 and it find a {, then add a match in the counter.
        ## END{print count} print the result.
        
        if [[ "$(awk '/{/ {d++} /}/ {d--} /{/ && d==2 {count++} END{print count}' /etc/srvctl/hosts.json)" == 1 ]]
        then
            echo false
            return
        fi
        
        echo true
        return
    fi
fi


echo false
