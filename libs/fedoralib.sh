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
    
    function msg_version_installed {
        ## by package manager
        local i v info
        if info="$(dnf info installed "$1" 2> /dev/null)"
        then
            v=$(echo "$info" | grep -m1 Version)
            i=$(echo "$info" | grep -m1 installed)
            msg "$1 ${v:13:8} ${i:13}"
        else
            ntc "$1 not installed"
        fi
    }
    
fi
