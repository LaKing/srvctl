#!/bin/bash

function reset_modules() {
    
    rm -fr /var/local/srvctl/modules.conf
    
    rm -fr /home/*/.srvctl/modules.conf
    
}
