#!/bin/bash

## running when sourced - no dependencies

## only root has permittions to write to that file
if $SC_ROOT
then
    
    
    ## the complication is to add to autocomplete
    function complicate {
        SC_COMMAND_LIST="$SC_COMMAND_LIST $*"
    }
    
    readonly SC_COMMAND_COMPLETION_DEFINITIONS=/etc/bash_completion.d/srvctl
    
    function update_command_completion {
        
        SC_COMMAND_LIST='help'
        
        for sourcefile in $SC_INSTALL_DIR/commands/*.sh
        do
            local file
            file="$(basename "$sourcefile")"
            [[ -f $sourcefile ]] && complicate "${file:0: -3}"
        done
        
        if [ -d /root/srvctl-includes ] && [ ! -z "$(ls /root/srvctl-includes)" ]
        then
            for sourcefile in /root/srvctl-includes/*
            do
                local file
                file="$(basename "$sourcefile")"
                [[ -f $sourcefile ]] && complicate "${file:0: -3}"
            done
        fi
        
        # shellcheck disable=SC2016
        local comp_words='${COMP_WORDS[COMP_CWORD]}'
        
        # shellcheck disable=SC2016
        local compreply='$(compgen -W "'"$SC_COMMAND_LIST"'" -- $curr_arg )'
        
cat > $SC_COMMAND_COMPLETION_DEFINITIONS << EOF
## fedora $SRVCTL generated files for bash autocomplete

_fedora_srvctl_options() {
    local curr_arg;
    curr_arg=$comp_words
    COMPREPLY=( $compreply );
}

complete -F _fedora_srvctl_options sc
complete -F _fedora_srvctl_options srvctl

EOF
        
        source $SC_COMMAND_COMPLETION_DEFINITIONS
        
        #dbg "Updated command completion"
        
    }
    
    ## check if command completion works and save loaded command completion words
    if [[ ! -f $SC_COMMAND_COMPLETION_DEFINITIONS ]] || $DEBUG
    then
        update_command_completion
    fi
    
fi

## TODO make it work without sourcing the definitions manually.
