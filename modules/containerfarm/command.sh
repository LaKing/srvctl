#!/bin/bash

## @@@ VE command | VE [shellcommand]
## @en give direct commands, or use direct shell access to containers.
## &en A shell command is executed in a container shell.
## &en Commands may have arguments as well.


## this is a special command, as it has several ways to be invoked
## we assume this as default command.

source "$SC_INSTALL_DIR/modules/srvctl/command.sh"

if [[ $CMD == show ]] || [[ $CMD == status ]] && [[ ! -z $ARG ]]
then
    C="$ARG"
    if [[ -d /srv/$C ]]
    then
        run machinectl "$CMD" "$C"
        exit
    else
        err "Container $C does not exist"
        exit
    fi
fi

if [[ $CMD == reboot ]] || [[ $CMD == poweroff ]] || [[ $CMD == kill ]] || [[ $CMD == login ]] || [[ $CMD == show ]] || [[ $CMD == status ]] && [[ ! -z $ARG ]]
then
    C="$ARG"
    
    if [[ -d /srv/$C ]]
    then
        
        if [[ "$(machinectl show $C | grep State)" != "State=running" ]]
        then
            err "$C not running"
            exit
        fi
        
        run machinectl "$CMD" "$ARG"
        exit
    else
        err "Container $C does not exist"
        exit
    fi
fi

if [[ -d /srv/$CMD ]]
then
    C="$CMD"
    
    if [[ $ARG == show ]] || [[ $ARG == status ]]
    then
        run machinectl "$ARG" "$C"
        exit
    fi
    
    
    if [[ "$(machinectl show $C | grep State)" != "State=running" ]]
    then
        err "$C not running"
        exit
    fi
    
    if [[ $ARG == reboot ]] || [[ $ARG == poweroff ]] || [[ $ARG == kill ]] || [[ $ARG == login ]] || [[ $ARG == show ]] || [[ $ARG == status ]]
    then
        run machinectl "$ARG" "$C"
    fi
    
    if [[ -f /srv/$C/rootfs/usr/bin/$ARG ]]
    then
        run machinectl shell "$C" "/usr/bin/$ARG $OPAS3"
        exit
    fi
    
    run machinectl shell "$SC_COMMAND_ARGUMENTS"
    exit
fi

#err "Container $CMD does not exist."
#exit
