#!/bin/bash

## optional - help execution main parameter - to allow optional arguments
readonly HEMP='## @@@'
## mandatory - the singe hint string
readonly HINT='## @en'
## mandatory - the multistring help
readonly HELP='## &en'

# No Color
readonly CLEAR='\e[0m'
## functions common to all areas of srvctl
function hint {
    if [ ! -z "$1" ]
    then
        ## print formatted hint
        printf "${GREEN}%-40s${CLEAR}" "   $1"
        printf "${GREEN}%-48s${CLEAR}" " $2"
        ## newline
        echo ''
    fi
}
function title {
    if [ ! -z "$1" ]
    then
        echo ''
        printf "${GREEN}"%-40s"${CLEAR}" "$1"
        echo ''
        echo ''
    fi
}

function load_libs {
    
    for sourcefile in $SC_INSTALL_DIR/libs/*
    do
        [[ -f "$sourcefile" ]] && source "$sourcefile"
    done
}


function run_command {
    
    [ ! -z "$CMD" ] || return 54
    
    ## permissions will determine the visibility of these commands
    if [ -f "/root/srvctl-includes/$CMD.sh" ]
    then
        source "/root/srvctl-includes/$CMD.sh"
        exif "$CMD failed"
        return "$?"
    fi
    ## the default srvctl commands
    if [ -f "$SC_INSTALL_DIR/commands/$CMD.sh" ]
    then
        source "$SC_INSTALL_DIR/commands/$CMD.sh"
        exif "$CMD failed"
        return "$?"
    fi
    
    ## custom by user
    if [ -f "$SC_HOME/srvctl-includes/$CMD.sh" ] && [ "$SC_HOME" != "/root" ]
    then
        source "$SC_HOME/srvctl-includes/$CMD.sh"
        exif "$CMD failed"
        return "$?"
    fi
    
    ## fall for adjust-service
    if [ "$ARG" == "enable" ] || [ "$ARG" == "start" ] || [ "$ARG" == "restart" ] || [ "$ARG" == "stop" ] || [ "$ARG" == "status" ]  || [ "$ARG" == "disable" ] || [ "$ARG" == "kill" ] \
    || [ "$CMD" == "enable" ] || [ "$CMD" == "start" ] || [ "$CMD" == "restart" ] || [ "$CMD" == "stop" ] || [ "$CMD" == "status" ]  || [ "$CMD" == "disable" ] || [ "$CMD" == "kill" ]
    then
        ## run the default command : adjust service
        source "$SC_INSTALL_DIR/commands/adjust-service.sh"
        exif "srvctl $ARGS FAILED"
        return "$?"
    fi
    
    return 4
}

function hint_on_file {
    
    [[ -f "$1" ]] || return 132
    
    head "$1" | grep -q 'root_only || return' && return 133
    
    local hintstr command hintcmd
    
    hintstr="$(head "$1" | grep -m 1 "$HINT")"
    command="$(basename "$1")"
    hintcmd="$(head "$1" | grep -m 1 "$HEMP" "$1")"
    
    if [ -z "$hintcmd" ]
    then
        hint "${command:0: -3}" "${hintstr:7}"
    else
        hint "${hintcmd:7}" "${hintstr:7}"
    fi
}

function hint_commands {
    
    msg "Usage: srvctl command [argument]"
    msg "  currently available commands for $SC_USER"
    if [ -d "$SC_HOME/srvctl-includes" ] && [ "$SC_HOME" != "/root" ]
    then
        title "COMMAND"
    else
        echo ""
    fi
    
    if [ -d /root/srvctl-includes ]
    then
        [ "$SC_ROOT_USERNAME" != root ] && title "COMMAND - from $SC_ROOT_USERNAME"
        [ "$SC_ROOT_USERNAME" == root ] && title "COMMAND - from root"
        for sourcefile in /root/srvctl-includes/*.sh
        do
            hint_on_file "$sourcefile"
        done
        title "COMMAND - from srvctl"
    fi
    
    for sourcefile in $SC_INSTALL_DIR/commands/*.sh
    do
        hint_on_file "$sourcefile"
    done
    
    if [ -d "$SC_HOME/srvctl-includes" ] && [ "$SC_HOME" != "/root" ]
    then
        title "COMMAND - from $SC_USER"
        for sourcefile in $SC_HOME/srvctl-includes/*.sh
        do
            hint_on_file "$sourcefile"
        done
    fi
    
    ## print formatted hint about man
    hint "help [COMMAND]" "See more detailed descriptions about COMMAND or about all commands."
    ## newline
    echo ''
    echo ''
}

function help_on_file {
    [[ -f "$1" ]] || return 133
    
    local hintstr command
    hintstr="$(head "$1" | grep "$HINT")"
    command="$(basename "$1")"
    hint "${command:0: -3}" "${hintstr:7}"
    printf "${YELLOW}%-4s" ""
    echo ''
    grep "$HELP" "$1" | sed "s/$HELP/    /g"
    printf "${CLEAR}%-4s" ""
    echo ""
}

function help_commands {
    
    title "srvctl COMMAND [arguments]"
    title "COMMAND"
    
    if [ -z "$ARG" ]
    then
        
        if [ -d /root/srvctl-includes ]
        then
            [ "$SC_ROOT_USERNAME" != root ] && title "COMMAND - from $SC_ROOT_USERNAME"
            [ "$SC_ROOT_USERNAME" == root ] && title "COMMAND - from root"
            for sourcefile in /root/srvctl-includes/*.sh
            do
                help_on_file "$sourcefile"
            done
            title "COMMAND - from srvctl"
        fi
        
        for sourcefile in $SC_INSTALL_DIR/commands/*.sh
        do
            help_on_file "$sourcefile"
        done
        
        if [ -d "$SC_HOME/srvctl-includes" ] && [ "$SC_HOME" != "/root" ]
        then
            title "COMMAND - from $SC_USER"
            for sourcefile in $SC_HOME/srvctl-includes/*.sh
            do
                help_on_file "$sourcefile"
            done
        fi
        
        return 0
    else
        local arg
        arg="${ARG,,}"
        
        if [ -f "/root/srvctl-includes/$arg.sh" ]
        then
            help_on_file "/root/srvctl-includes/$arg.sh"
            msg "Custom command from root"
            return
        fi
        
        if [ -f "$SC_INSTALL_DIR/commands/$arg" ]
        then
            help_on_file "$SC_INSTALL_DIR/commands/$arg.sh"
            msg "srvctl v3 command"
            return
        fi
        
        if [ -f "$SC_HOME/srvctl-includes/$arg.sh" ] && [ "$SC_HOME" != "/root" ]
        then
            help_on_file "$SC_HOME/srvctl-includes/$arg.sh"
            msg "Custom command defined in $SC_HOME/srvctl-includes/$arg.sh"
            return
        fi
        
        err "Pardon? '$ARG' is not a command"
        return 46
    fi
    
}


#function hint_cms {
#    for sourcefile in $SC_INSTALL_DIR/ve-cms/*
#    do
#        [[ -f "$sourcefile" ]] && source "$sourcefile"
#    done
#}

