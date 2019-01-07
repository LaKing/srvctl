#!/bin/bash

function reset_modules() {
    msg "reset modules"
    rm -fr /var/local/srvctl/modules.conf
    
    rm -fr /home/*/.srvctl/modules.conf
    
}
