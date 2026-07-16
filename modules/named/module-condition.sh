#! /bin/bash

## modules/named/module-condition.sh
## Module condition for the named module, evaluated at init in a subshell;
## the value echoed on stdout is cached in modules.conf as SC_USE_NAMED.
## Enabled only on designated DNS hosts: SC_DNS_SERVER must be exactly
## 'master' or 'slave'. SC_DNS_SERVER comes from the host's dns_server key
## in /etc/srvctl/clusters.json, exported into /var/srvctl3/host/host.conf by
## modules/containers/host-conf.js and sourced by init.sh.

if [[ $SC_DNS_SERVER == 'master' ]] || [[ $SC_DNS_SERVER == 'slave' ]]
then
    echo true
    return
fi

echo false
return
