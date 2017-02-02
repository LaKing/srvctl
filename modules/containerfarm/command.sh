#!/bin/bash

## @@@ VE command | VE [shellcommand]
## @en give direct commands, or use direct shell access to containers.
## &en A shell command is executed in a container shell.
## &en Commands may have arguments as well.


## this is a special command, as it has several ways to be invoked
## we assume this as default command.

source "$SC_INSTALL_DIR/modules/srvctl/command.sh"

C='?'

## for example, sc !
if [[ $CMD == restart ]]
then
    return
fi

cop="shell"

if [[ $CMD == reboot ]] || [[ $CMD == poweroff ]] || [[ $CMD == kill ]] || [[ $CMD == login ]] || [[ $CMD == show ]] || [[ $CMD == status ]] || [[ $CMD == show ]] || [[ $CMD == status ]]
then
    cop="$CMD"
fi

if [[ $ARG == reboot ]] || [[ $ARG == poweroff ]] || [[ $ARG == kill ]] || [[ $ARG == login ]] || [[ $ARG == show ]] || [[ $ARG == status ]] || [[ $ARG == show ]] || [[ $ARG == status ]]
then
    cop="$ARG"
fi


if [[ -d /srv/$CMD ]]
then
    C="$CMD"
fi

if [[ $ARG ]] && [[ -d /srv/$ARG ]]
then
    C="$ARG"
fi

if [[ -z $C ]]
then
    return
fi

if [[ "$cop" == "$C" ]]
then
    return
fi

if [[ ! -d /srv/$C ]]
then
    return
fi

if [[ $cop == reboot ]] || [[ $cop == poweroff ]] || [[ $cop == kill ]] || [[ $cop == login ]] || [[ $cop == show ]] || [[ $cop == status ]] || [[ $cop == show ]] || [[ $cop == status ]] || [[ $cop == shell ]]
then
    msg "$C $cop"
else
    return
fi

if ! run machinectl show "$C" 2> /dev/null
then
    err "$C not running"
    return
fi

if [[ $cop == shell ]]
then
    if [[ -f /srv/$C/rootfs/usr/bin/$ARG ]]
    then
        run machinectl shell "$C" "/usr/bin/$ARG $OPAS3"
        exit
    fi
    
    run machinectl shell "$SC_COMMAND_ARGUMENTS"
else
    run machinectl "$cop" "$C" --no-pager
fi
exit
#return 1
