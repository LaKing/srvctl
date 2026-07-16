#!/bin/bash

##
##   containers/module-condition.sh — module activation test.
##
##   Sourced in a subshell by test_srvctl_modules (commonlib.sh); must
##   print "true" to enable the module (cached as SC_USE_CONTAINERS in
##   modules.conf). Enabled on configured cluster hosts: never on a
##   pristine localhost.localdomain, never inside a container
##   (systemd-nspawn/lxc), only when this HOSTNAME is listed in
##   /var/srvctl3/host/hosts.json — plus the explicit first-install state set by
##   init.sh only after ARG was validated in the canonical topology.
##
##   Note: host-conf.js in this directory is invoked directly by core
##   init.sh even when this condition says false.
##

if [[ ${SC_CLUSTER_HOSTNAME_BOOTSTRAP:-false} == true ]] && \
   [[ -n ${SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME:-} ]]
then
    echo true
    return
fi

if [[ $HOSTNAME == localhost.localdomain ]]
then
    echo false
    return
fi

if [[ $SC_HOSTNET ]] || [[ -d /etc/srvctl/data ]]
then

    SC_VIRT="$(systemd-detect-virt -c)"
    readonly SC_VIRT

    ## lxc is deprecated, but we can consider it a container ofc.
    if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
    then
        echo false
        return
    fi
    
    if [[ -f /var/srvctl3/host/hosts.json ]] && grep --quiet "\"$HOSTNAME\"" /var/srvctl3/host/hosts.json
    then
        echo true
        return
    fi
fi

echo false
