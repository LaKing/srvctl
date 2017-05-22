#!/bin/bash

function restart_opendkim {
    
    chown -R opendkim:opendkim /var/opendkim
    
    systemctl restart opendkim.service
    
    test=$(systemctl is-active opendkim.service)
    
    if [ "$test" == "active" ]
    then
        msg "restarted opendkim.service"
    else
        ## syntax check
        
        err "opendkim restart FAILED!"
        systemctl status opendkim.service --no-pager
    fi
}
