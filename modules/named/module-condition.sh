#! /bin/bash

if [[ $SC_DNS_SERVER == 'master' ]] || [[ $SC_DNS_SERVER == 'slave' ]]
then
    echo true
    return
fi

echo false
return
#source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
