#!/bin/bash

function restart_haproxy {
    
    systemctl restart haproxy.service
    
    test=$(systemctl is-active haproxy.service)
    
    if [ "$test" == "active" ]
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
    
    systemctl reload haproxy.service
    
    test=$(systemctl is-active haproxy.service)
    
    if [ "$test" == "active" ]
    then
        msg "reloaded haproxy.service"
    else
        ## haproxy syntax check
        haproxy -c -f /etc/haproxy/haproxy.cfg
        
        err "HAproxy reload FAILED!"
        systemctl status haproxy.service --no-pager
        
        restart_haproxy
    fi
    
    ## haproxy needs a second to start serving, and we have named asking for data from haproxy ...
    run 'sleep 1'
}