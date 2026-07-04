#!/bin/bash

function restart_haproxy {
    
    systemctl restart haproxy.service
    
    
    if systemctl is-active haproxy.service
    then
        msg "restarted haproxy.service"
    else
        ## haproxy syntax check
        haproxy -c -f /etc/haproxy/haproxy.cfg
        
        err "HAproxy restart FAILED!"
        systemctl status haproxy.service --no-pager
    fi
    
    ## haproxy needs a second to start serving, and we have named asking for data from haproxy ...
    run 'sleep 1'
}

function reload_haproxy {
    
    if systemctl reload haproxy.service
    then
        msg "reloaded haproxy.service"
    fi
    
    run 'sleep 1'
    if systemctl is-active haproxy.service
    then
    	msg "haproxy.service active"
    else
    	## haproxy syntax check

    	err "HAproxy INACTIVE"
    	systemctl status haproxy.service --no-pager

    	restart_haproxy
    fi
    
    
    ## haproxy needs a second to start serving, and we have named asking for data from haproxy ...
    run 'sleep 1'
}