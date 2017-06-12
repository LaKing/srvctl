#!/bin/bash
#### machinectl commands
## @@@ VE command | VE [shellcommand]
## @en give direct commands, or use direct shell access to containers.
## &en A shell command is executed in a container shell.
## &en Commands may have arguments as well.

#### these specs are used in the gui
## spec //containerfarm×status×get the container status×status VE
## spec //containerfarm×show×show container parameters×poweroff VE
## spec //containerfarm×reboot×reboot a container×reboot VE
## spec //containerfarm×poweroff×poweroff a container×poweroff VE
## spec //containerfarm×kill×kill a container with all processes×kill VE

## this is a special command, as it has several ways to be invoked
## we assume this as default command.

source "$SC_INSTALL_DIR/modules/srvctl/command.sh"

C='?'

## for example, sc !
if [[ $CMD == restart ]]
then
    echo "return from $CMD"
    return
fi

cop="shell"

if [[ $CMD == reboot ]] || [[ $CMD == poweroff ]] || [[ $CMD == kill ]] || [[ $CMD == login ]] || [[ $CMD == show ]] || [[ $CMD == status ]]
then
    cop="$CMD"
fi

if [[ $ARG == reboot ]] || [[ $ARG == poweroff ]] || [[ $ARG == kill ]] || [[ $ARG == login ]] || [[ $ARG == show ]] || [[ $ARG == status ]]
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

if [[ $cop == reboot ]] || [[ $cop == poweroff ]] || [[ $cop == kill ]] || [[ $cop == login ]] || [[ $cop == show ]] || [[ $cop == status ]] || [[ $cop == shell ]]
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
        exif
        exit 0
    fi
    
    run machinectl shell "$SC_COMMAND_ARGUMENTS"
else
    run machinectl "$cop" "$C" --no-pager
fi

err "Command could not be interpreted."
exit 35
#return 1
