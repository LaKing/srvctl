#!/bin/bash

##
##   modules/firewalld/module-condition.sh — module activation test.
##
##   Sourced in a subshell by test_srvctl_modules (commonlib.sh); must
##   print "true" or "false". The result is cached as SC_USE_FIREWALLD
##   in modules.conf. Enabled:
##     - inside any systemd-nspawn or lxc container,
##     - on farm hosts (SC_HOSTNET set or /etc/srvctl/data present, and
##       $HOSTNAME listed in /var/srvctl3/host/hosts.json),
##     - on the 'update-install <host>' bootstrap path.
##   Never on a pristine localhost.localdomain machine.
##

if [[ $HOSTNAME == localhost.localdomain ]]
then
    echo false
    return
fi

## subshell-scoped: conditions are sourced inside $( ), so this readonly
## does not leak into the main shell.
SC_VIRT=$(systemd-detect-virt -c)
readonly SC_VIRT

## lxc is deprecated, but we can consider it a container ofc.
if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
then
    echo true
    return
fi

## farm host: part of a cluster and listed among the managed hosts.
if [[ $SC_HOSTNET ]] || [[ -d /etc/srvctl/data ]]
then
    if [[ -f /var/srvctl3/host/hosts.json ]] && grep --quiet "\"$HOSTNAME\"" /var/srvctl3/host/hosts.json
    then
        echo true
        return
    fi
fi

## bootstrap: first 'sc update-install HOST' on a fresh machine.
if [[ $CMD == update-install ]] && [[ $ARG ]]
then
    echo true
    return
fi

echo false
