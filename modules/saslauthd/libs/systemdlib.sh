#!/bin/bash

function restart_saslauthd {
    
    systemctl restart saslauthd.service
    
    test=$(systemctl is-active saslauthd.service)
    
    if [ "$test" == "active" ]
    then
        msg "restarted saslauthd.service"
    else
        err "saslauthd restart FAILED!"
        systemctl status saslauthd.service --no-pager
    fi
    
}
