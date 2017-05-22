#!/bin/bash

function restart_pound {
    
    systemctl restart pound.service
    
    test=$(systemctl is-active pound.service)
    
    if [ "$test" == "active" ]
    then
        msg "restarted pound.service"
    else
        ## pound syntax check
        pound -c -f /etc/pound.cfg
        
        err "Pound restart FAILED!"
        systemctl status pound.service --no-pager
    fi
}
