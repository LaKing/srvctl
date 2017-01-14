#! /bin/bash

if [[ $SC_DNS_SERVER == 'named' ]]
then
    echo true
    return
fi

source "$SC_INSTALL_DIR/modules/containerfarm/module-condition.sh"
