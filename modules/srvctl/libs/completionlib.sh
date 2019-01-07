#!/bin/bash

## invoke silently with:
## (generate_completion &>/dev/null &)

function generate_completion() {
    msg "Writing command-completion data"
    if $SC_ROOT
    then
        mkdir -p /var/local/srvctl/completion
        chmod 777 /var/local/srvctl/completion
    fi
    
    local complicated_commands sc_user
    
    sc_user="$1"
    
    if [[ -z "$sc_user" ]]
    then
        # shellcheck disable=SC2153
        sc_user="$SC_USER"
    fi
    
    complicated_commands="help man"
    rm -fr /var/local/srvctl/completion/"$sc_user".arguments
    
    function complicate() {
        local command
        command="$1"
        complicated_commands="$complicated_commands ${command/%\ */}"
        if [[ $command == *" "* ]] && [[ $command != *" NAME"* ]]
        then
            echo "$command" >> /var/local/srvctl/completion/"$sc_user".arguments
        fi
    }
    
    hint_commands > /var/local/srvctl/completion/"$sc_user".hints
    msg "Wrote $sc_user.hints"
    
    ## the arguments file is written in the function
    chmod 660 /var/local/srvctl/completion/"$sc_user".arguments
    msg "Wrote $sc_user.arguments"
    
    ## skip capital letter commands
    # shellcheck disable=SC2001
    echo "$complicated_commands" | sed 's/[A-Z]//g' > /var/local/srvctl/completion/"$sc_user".commands
    chmod 660 /var/local/srvctl/completion/"$sc_user".commands
    msg "Wrote $sc_user.commands"
    
    if $SC_USE_CONTAINERS
    then
        cfg user container_list > /var/local/srvctl/completion/"$sc_user".VE
        chmod 660 /var/local/srvctl/completion/"$sc_user".VE
        msg "Wrote $sc_user.VE list"
    fi
    
    for i in ~/.config/systemd/user/* /etc/systemd/user/* $XDG_RUNTIME_DIR/systemd/user/* /run/systemd/user/* ~/.local/share/systemd/user/* /usr/lib/systemd/user/*
    do
        if [[ -f $i ]]
        then
            unitfiles="$unitfiles $(basename "$i")"
        fi
    done
    
    for i in /usr/lib/systemd/system/* /etc/systemd/system/* /etc/systemd/system/*/* /run/systemd/system/*
    do
        if [[ -f $i ]]
        then
            unitfiles="$unitfiles $(basename "$i")"
        fi
    done
    
    echo "$unitfiles" > /var/local/srvctl/completion/"$sc_user".units
    chmod 660 /var/local/srvctl/completion/"$sc_user".units
    msg "Wrote $sc_user.units"
}