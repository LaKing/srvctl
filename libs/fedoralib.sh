#!/bin/bash

if [ "$ID" == fedora ]
then
    
    function sc_install {
        # shellcheck disable=SC2048
        # shellcheck disable=SC2086
        run dnf -y install $*
    }
    
    function sc_update {
        # shellcheck disable=SC2048
        # shellcheck disable=SC2086
        run dnf -y update $*
    }
    
fi
