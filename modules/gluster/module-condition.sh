#! /bin/bash

###
###        gluster module condition
###
###        Sourced at init; must output exactly "true" to enable the module.
###        The result is cached as SC_USE_GLUSTER in modules.conf.
###
###        Intended logic: enable only on real (non-container) cluster hosts
###        listed in /var/srvctl3/host/hosts.json alongside at least one other host.
###        At this commit the module is HARD-DISABLED: even the final
###        "all checks passed" branch echoes false (kill-switch introduced in
###        commit e179f53), so its libs are never sourced and its hooks never
###        run. The module is a deprecation candidate for v4.
###

if [[ $HOSTNAME == localhost.localdomain ]]
then
    echo false
    return
fi

if [[ $SC_HOSTNET ]] || [[ -d /etc/srvctl/data ]]
then
    
    SC_VIRT=$(systemd-detect-virt -c)
    readonly SC_VIRT
    
    ## lxc is deprecated, but we can consider it a container ofc.
    if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
    then
        echo false
        return
    fi
    
    if [[ -f /var/srvctl3/host/hosts.json ]] && grep --quiet "\"$HOSTNAME\"" /var/srvctl3/host/hosts.json
    then
        
        ## check if we have servers in this cluster
        ## /{/ {d++} if { is found, increment the depth variable.
        ## /}/ {d--} if } is found, decrement the depth variable.
        ## /{/ && d==2 {count++} count each { seen at depth 2, i.e. one per
        ##                       host object nested inside the outer {}.
        ## END{print count} print the result.
        
        if [[ "$(awk '/{/ {d++} /}/ {d--} /{/ && d==2 {count++} END{print count}' /var/srvctl3/host/hosts.json)" == 1 ]]
        then
            echo false
            return
        fi
        
        ## FIXME(v4): deliberate kill-switch — the success branch echoes false
        ## ("#echo true" kept below as the record of it). This silently turns
        ## off gluster replication, the /var/srvctl3/gluster/* RO mounts and
        ## cert renewal on every cluster host; downstream consumers (datastore
        ## RO dir, ssh pubkey lookup) get no warning that their paths are
        ## unmounted. Decide the module's fate in v4 (delete or restore behind
        ## an explicit config flag).
        echo false
        #echo true
        return
    fi
fi


echo false
