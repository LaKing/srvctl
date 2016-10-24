#!/bin/bash

readonly SC_COMMAND_COMPLETION_DEFINITIONS=/etc/bash_completion.d/srvctl


function update_command_completion {
    
    # shellcheck disable=SC2016
    local comp_words='${COMP_WORDS[COMP_CWORD]}'
    
    # shellcheck disable=SC2016
    local compreply='$(compgen -W "'"$SC_COMMAND_LIST"'" -- $curr_arg )'
    
cat > $SC_COMMAND_COMPLETION_DEFINITIONS << EOF
## fedora-srvctl generated files for bash autocomplete

_fedora_srvctl_options() {
    local curr_arg;
    curr_arg=$comp_words
    COMPREPLY=( $compreply );
}

complete -F _fedora_srvctl_options sc
complete -F _fedora_srvctl_options srvctl

EOF
    
    source $SC_COMMAND_COMPLETION_DEFINITIONS
    
}


