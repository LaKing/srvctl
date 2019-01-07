#!/bin/bash

(bash /usr/local/share/srvctl/srvctl.sh complicate &>/dev/null &)

_fedora_srvctl_options() {
    
    local SC_USER
    
    ## determine the proper user
    if [[ -z $SUDO_USER ]]
    then
        SC_USER="$USER"
    else
        SC_USER="$SUDO_USER"
    fi
    
    #echo "SRVCTL_OPTIONS $SC_USER"
    
    ## these are the current arguments while typing
    local curr_arg;
    curr_arg=${COMP_WORDS[COMP_CWORD]}
    
    #echo "@ ${#COMP_WORDS[@]} @"
    
    ## the list will contain those words we can assume for now to be relevant
    local list length command CMD arr argument
    list=""
    length=${#COMP_WORDS[@]}
    sc_user="/var/local/srvctl/completion/$SC_USER"
    
    ## the command
    if [[ $length == 2 ]]
    then
        list="$list start stop restart enable disable status kill help complicate"
        [[ -f "$sc_user.commands" ]] && list="$list $(cat "$sc_user.commands")"
        [[ -f "$sc_user.units" ]] && list="$list $(cat "$sc_user.units")"
        [[ -f "$sc_user.VE" ]] && list="$list $(cat "$sc_user.VE")"
    fi
    
    if [[ $length == 3 ]]
    then
        CMD="${COMP_WORDS[1]}"
        if [[ $CMD == enable ]] || [[ $CMD == start ]] || [[ $CMD == restart ]] || [[ $CMD == stop ]] || [[ $CMD == status ]]  || [[ $CMD == disable ]] || [[ $CMD == kill ]]
        then
            [[ -f "$sc_user.units" ]] && list="$list $(cat "$sc_user.units")"
            [[ -f "$sc_user.VE" ]] && list="$list $(cat "$sc_user.VE")"
        else
            list="$list start stop restart enable disable status kill help complicate"
        fi
    fi
    
    ## the arguments
    if (( length > 2 )) && [[ -f "$sc_user.arguments" ]]
    then
        ## CMD is the srvctl-command we consider now
        CMD="${COMP_WORDS[1]}"
        command="$(grep "$CMD" "$sc_user".arguments)"
        arr=("$command")
        argument=${arr[$length-2]}
        list="$list $(echo "$argument" | sed 's/[A-Z]//g' | tr '[' ' ' | tr ']' ' ' | tr '|' ' ' )"
        if [[ -f "$sc_user.$argument" ]]
        then
            list="$(cat "$sc_user.$argument")"
        fi
    fi
    ## TODO Prefer mapfile or read -a to split command output (or quote to avoid splitting).
    # shellcheck disable=SC2207
    COMPREPLY=( $(compgen -W "$list" -- "$curr_arg" ) );
}

complete -F _fedora_srvctl_options sc
complete -F _fedora_srvctl_options srvctl

function display() {
    local hints
    if [[ -z $SUDO_USER ]]
    then
        hints=/var/local/srvctl/completion/"$USER".hints
    else
        hints=/var/local/srvctl/completion/"$SUDO_USER".hints
    fi
    if [[ ! -f $hints ]]
    then
        sleep 1
    fi
    if [[ -f $hints ]]
    then
        cat "$hints"
    else
        echo 'no hints'
    fi
}

display