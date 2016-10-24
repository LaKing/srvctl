#!/bin/bash
local command='update-install'

complicate "$command"
hint "$command" "Run the installation/update script."
manual '
    Install all components
'

## first, update the system
if [[ "$CMD" == "$command" ]]
then
    
    run dnf -y update
    
    ok
fi

