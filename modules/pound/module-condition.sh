#! /bin/bash

if [[ $SC_REVERSE_PROXY == 'pound' ]]
then
    echo true
    return
fi

source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
