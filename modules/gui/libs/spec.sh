#!/bin/bash

function make_commands_spec_on_file() {
    [[ ! -f $1 ]] && return
    head "$1" | grep -q 'root_only' && return
    head "$1" | grep -q '## interactive' && return
    local hintstr command
    
    command="$(basename "$1")"
    hintstr="$(head "$1" | grep "$HINT")"
    hintcmd="$(head "$1" | grep -m 1 "$HEMP" "$1")"
    
    command="${command:0: -3}"
    hintstr="${hintstr:7}"
    hintcmd="${hintcmd:7}"
    
    echo "$1×$command×$hintstr×$hintcmd" >> /var/local/srvctl/commands.spec
    
}

function make_commands_spec() {
    msg "Make user commands spec for srvctl-gui."
    rm -fr /var/local/srvctl/commands.spec
    
    for sourcefile in /root/srvctl-includes/*.sh
    do
        make_commands_spec_on_file "$sourcefile"
    done
    
    for sourcefile in $SC_INSTALL_DIR/modules/*/commands/*.sh
    do
        make_commands_spec_on_file "$sourcefile"
    done
    
    for homedir in /home/*
    do
        if [ -d "$homedir/srvctl-includes" ]
        then
            for sourcefile in $homedir/srvctl-includes/*.sh
            do
                make_commands_spec_on_file  "$sourcefile"
            done
        fi
    done
    
    local tvhc module
    for dir in $SC_INSTALL_DIR/modules/*
    do
        module="${dir##*/}"
        tvhc="SC_USE_${module^^}"
        
        if [[ ${!tvhc} == true ]]
        then
            if [[ -f "$dir/command.sh" ]]
            then
                grep "## spec" "$dir/command.sh" >> /var/local/srvctl/commands.spec
            fi
        fi
    done
    ## We dont read individual user commands
}
