#!/bin/bash

function restart_named {
    
    systemctl restart named.service
    
    test=$(systemctl is-active named.service)
    
    if [ "$test" == "active" ]
    then
        msg "restarted named.service"
    else
        ## syntax check
        named-checkconf
        
        err "named restart FAILED!"
        systemctl status named.service --no-pager
    fi
}
