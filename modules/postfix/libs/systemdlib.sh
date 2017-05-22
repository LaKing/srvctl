#!/bin/bash

function restart_postfix {
    
    systemctl restart postfix.service
    
    test=$(systemctl is-active postfix.service)
    
    if [ "$test" == "active" ]
    then
        msg "restarted postfix.service"
    else
        ## syntax check
        postfix check
        
        err "Postfix restart FAILED!"
        systemctl status postfix.service --no-pager
    fi
}
