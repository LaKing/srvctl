#!/bin/bash
#### machinectl commands
## @@@ VE command | VE [shellcommand]
## @en give direct commands, or use direct shell access to containers.
## &en A shell command is executed in a container shell.
## &en Commands may have arguments as well.

#### these specs are used in the gui
## spec //containers×status×get the container status×status VE
## FIXME(v4): the 'show' spec below carries the action 'poweroff VE' — a GUI
## executing these specs would power the container off on a 'show' click.
## spec //containers×show×show container parameters×poweroff VE
## spec //containers×reboot×reboot a container×reboot VE
## spec //containers×poweroff×poweroff a container×poweroff VE
## spec //containers×kill×kill a container with all processes×kill VE

## this is a special command, as it has several ways to be invoked
## we assume this as default command.

##
##   containers/command.sh — module default command: the 'sc VE op' /
##   'sc op VE' shorthand for machinectl operations on a local container.
##
##   Sourced by run_commands (commonlib.sh) for every command word that did
##   not match a named command file. It first delegates to the generic
##   systemd service shorthand (modules/srvctl/command.sh), which runs the
##   adjust-service hook — our hooks/adjust-service.sh rewrites container
##   names to srvctl-nspawn@ units (stop+start instead of restart) and
##   handles 'all-containers OP' there. If that returns without acting,
##   this script maps reboot|poweroff|kill|login|show|status|shell (either
##   word order: 'sc VE op' or 'sc op VE') onto machinectl, provided
##   /srv/$C exists and the machine is running. 'shell' opens an
##   interactive machinectl shell and exits. Anything else falls through
##   with 'return' so dispatch can continue to other modules.
##

# shellcheck source=/usr/local/share/srvctl/modules/srvctl/command.sh
# shellcheck disable=SC1091 ## runtime-path
source "$SC_INSTALL_DIR/modules/srvctl/command.sh"

## placeholder that never names an existing /srv directory
C='?'

## for example, sc !
## FIXME(v4): a bare 'sc restart' (no service resolved upstream) lands here
## and prints the stray debug-style line "return from restart".
if [[ $CMD == restart ]]
then
    echo "return from $CMD"
    return
fi


if [[ -d /srv/$CMD ]]
then
    C="$CMD"
fi

if [[ $ARG ]] && [[ -d /srv/$ARG ]]
then
    C="$ARG"
fi

## dead check: C defaults to '?', so it is never empty here;
## the /srv/$C directory test below is the effective gate.
if [[ -z $C ]]
then
    return
fi

## cop = container operation; keeping cop == C marks "no operation found"
cop="$C"

if [[ $CMD == reboot ]] || [[ $CMD == poweroff ]] || [[ $CMD == kill ]] || [[ $CMD == login ]] || [[ $CMD == show ]] || [[ $CMD == status ]] || [[ $CMD == shell ]]
then
    cop="$CMD"
fi

if [[ $ARG == reboot ]] || [[ $ARG == poweroff ]] || [[ $ARG == kill ]] || [[ $ARG == login ]] || [[ $ARG == show ]] || [[ $ARG == status ]] || [[ $ARG == shell ]]
then
    cop="$ARG"
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
	run machinectl -q --no-pager shell "$C"
    exif
	exit 0

    ## FIXME(v4): everything from here to the end of this branch is
    ## unreachable — the exif/exit 0 pair above always terminates. The
    ## per-binary lookup and the mktemp exec workaround below (run cannot
    ## pass quoted arguments; see all_containers_execute for the live twin)
    ## are kept only as reference and are slated for deletion.
    if [[ -f /srv/$C/rootfs/usr/sbin/$ARG ]]
    then
        run machinectl -q --no-pager shell "$C" "/usr/sbin/$ARG $OPAS3"
        exif
        exit 0
    fi
    
    if [[ -f /srv/$C/rootfs/usr/bin/$ARG ]]
    then
        run machinectl -q --no-pager shell "$C" "/usr/bin/$ARG $OPAS3"
        exif
        exit 0
    fi
    
    if [[ -z "$ARG" ]]
    then
        run machinectl -q --no-pager shell "$C" /bin/bash && exit
        exif
        exit 0
    fi
    nur machinectl -q --no-pager shell "$C" "/bin/bash/ -c '$ARG $OPAS3'"
    temp_file=$(mktemp)
    echo "machinectl -q --no-pager shell $C /bin/bash/ -c '$ARG $OPAS3'" > "$temp_file"
    /bin/bash "$temp_file"
    rm -fr "$temp_file"
    
    exif
    exit 0
else
    run machinectl "$cop" "$C" --no-pager
    exif
    exit 0
fi

## unreachable tail: both branches above exit (kept for the exit 35 contract)
err "Command could not be interpreted."
exit 35
