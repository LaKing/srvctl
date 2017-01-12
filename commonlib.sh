#!/bin/bash

## run only with srvctl
[[ $SRVCTL ]] || exit 10

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
    
    ## print formatted hint
    printf "${GREEN}%-40s${CLEAR}" "   $1"
    printf "${GREEN}%-48s${CLEAR}" " $2"
    ## newline
    echo ''
    
}
function title {
    
    echo ''
    printf "${GREEN}"%-40s"${CLEAR}" "$1"
    echo ''
    echo ''
    
}

function load_libs {
    local tvll
    
    for dir in $SC_INSTALL_DIR/modules/*
    do
        tvll="SC_USE_${dir##*/}"
        if [[ ${!tvll} == true ]]
        then
            for sourcefile in $dir/libs/*
            do
                [[ $DEBUG == true ]] && ntc "@lib ${dir##*/} ${sourcefile##*/}"
                
                [[ -f $sourcefile ]] && source "$sourcefile"
            done
        fi
    done
}

function run_module_hook { ## module hook
    local dir hook
    dir="$SC_INSTALL_DIR/modules/$1"
    hook="$2"
    
    if [[ -f $dir/hooks/$hook.sh ]]
    then
        
        [[ $DEBUG == true ]] && ntc "@hook ${dir##*/} $hook"
        
        source "$dir/hooks/$hook.sh"
        exif "$dir hook '$hook' failed"
    fi
}

function run_hook {
    local hook tvrh
    hook="$1"
    for dir in $SC_INSTALL_DIR/modules/*
    do
        tvrh="SC_USE_${dir##*/}"
        
        if [[ ${!tvrh} == true ]]
        then
            
            ## find and call hooks
            if [[ -f $dir/hooks/$hook.sh ]]
            then
                
                [[ $DEBUG == true ]] && ntc "@hook ${dir##*/} $hook"
                
                source "$dir/hooks/$hook.sh"
                exif "$dir hook '$hook' failed"
            fi
        fi
    done
}

function run_hooks {
    run_hook "pre-$1"
    run_hook "$1"
    run_hook "post-$1"
}

function run_command {
    
    [[ $CMD ]] || return 54
    
    local tvrc
    
    ## permissions will determine the visibility of these commands
    if [[ -f /root/srvctl-includes/$CMD.sh ]]
    then
        source "/root/srvctl-includes/$CMD.sh"
        exif "'$CMD' failed"
        return
    fi
    
    for dir in $SC_INSTALL_DIR/modules/*
    do
        
        tvrc="SC_USE_${dir##*/}"
        if [[ ${!tvrc} == true ]]
        then
            
            ## find and run commands
            if [[ -f $dir/commands/$CMD.sh ]]
            then
                source "$dir/commands/$CMD.sh"
                exif "'$CMD' failed"
                return
            fi
        fi
    done
    
    ## custom by user
    if [[ -f $SC_HOME/srvctl-includes/$CMD.sh ]] && [[ $SC_HOME != /root ]]
    then
        source "$SC_HOME/srvctl-includes/$CMD.sh"
        exif "'$CMD' failed"
        return
    fi
    
    ## this is a special command, as it has several ways to be invoked
    if [[ -f "$SC_INSTALL_DIR/modules/srvctl/commands/adjust-service.sh" ]]
    then
        ## adjust-service
        if [[ $ARG == enable ]] || [[ $ARG == start ]] || [[ $ARG == restart ]] || [[ $ARG == stop ]] || [[ $ARG == status ]]  || [[ $ARG == disable ]] || [[ $ARG == kill ]] \
        || [[ $CMD == enable ]] || [[ $CMD == start ]] || [[ $CMD == restart ]] || [[ $CMD == stop ]] || [[ $CMD == status ]]  || [[ $CMD == disable ]] || [[ $CMD == kill ]]
        then
            source "$SC_INSTALL_DIR/modules/srvctl/commands/adjust-service.sh"
            exif "srvctl $ARGS failed"
            return
        fi
    fi
    
    ## call a srvctl function
    if [[ $CMD == 'exec-function' ]] && [[ $OPAS ]]
    then
        $OPAS
        exif "failed to exec '$OPAS'"
        return
    fi
    
    return 4
}

function hint_on_file {
    
    [[ -f $1 ]] || return 132
    
    ## root_only: if not root, and file marked as root_only skip this item
    ! $SC_ROOT && head "$1" | grep -q 'root_only' && return 133
    #! [[ $SC_HOSTNET ]] && head "$1" | grep -q 'hs_only' && return 134
    #! $SC_ON_VE && head "$1" | grep -q 've_only' && return 135
    
    local hintstr command hintcmd
    
    hintstr="$(head "$1" | grep -m 1 "$HINT")"
    command="$(basename "$1")"
    hintcmd="$(head "$1" | grep -m 1 "$HEMP" "$1")"
    
    if [[ -z $hintcmd ]]
    then
        hint "${command:0: -3}" "${hintstr:7}"
    else
        hint "${hintcmd:7}" "${hintstr:7}"
    fi
}

function hint_commands {
    
    msg "Usage: srvctl command [argument]"
    msg "  currently available commands for $SC_USER"
    if [[ -d $SC_HOME/srvctl-includes ]] && [[ $SC_HOME != /root ]]
    then
        title "COMMAND"
    else
        echo ""
    fi
    
    if [ -d /root/srvctl-includes ]
    then
        [[ $SC_ROOT_USERNAME != root ]] && title "COMMAND - from $SC_ROOT_USERNAME"
        [[ $SC_ROOT_USERNAME == root ]] && title "COMMAND - from root"
        for sourcefile in /root/srvctl-includes/*.sh
        do
            hint_on_file "$sourcefile"
        done
        title "COMMAND - from srvctl"
    fi
    
    local tvhc
    for dir in $SC_INSTALL_DIR/modules/*
    do
        
        tvhc="SC_USE_${dir##*/}"
        
        if [[ ${!tvhc} == true ]]
        then
            for sourcefile in $dir/commands/*.sh
            do
                hint_on_file "$sourcefile"
            done
        fi
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
    
    if [[ -z $ARG ]]
    then
        
        if [[ -d /root/srvctl-includes ]]
        then
            [[ $SC_ROOT_USERNAME != root ]] && title "COMMAND - from $SC_ROOT_USERNAME"
            [[ $SC_ROOT_USERNAME == root ]] && title "COMMAND - from root"
            for sourcefile in /root/srvctl-includes/*.sh
            do
                help_on_file "$sourcefile"
            done
            title "COMMAND - from srvctl"
        fi
        
        for sourcefile in $SC_INSTALL_DIR/modules/*/commands/*.sh
        do
            help_on_file "$sourcefile"
        done
        
        if [[ -d $SC_HOME/srvctl-includes ]] && [[ $SC_HOME != /root ]]
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
        
        if [[ -f /root/srvctl-includes/$arg.sh ]]
        then
            help_on_file "/root/srvctl-includes/$arg.sh"
            msg "Custom command from root"
            return
        fi
        
        for dir in $SC_INSTALL_DIR/modules/*
        do
            if [[ -f $dir/commands/$arg ]]
            then
                help_on_file "$dir/commands/$arg.sh"
                msg "srvctl v3 command"
                return
            fi
        done
        
        if [[ -f $SC_HOME/srvctl-includes/$arg.sh ]] && [[ $SC_HOME != /root ]]
        then
            help_on_file "$SC_HOME/srvctl-includes/$arg.sh"
            msg "Custom command defined in $SC_HOME/srvctl-includes/$arg.sh"
            return
        fi
        
        err "Pardon? '$ARG' is not a command"
        return 46
    fi
    
}

function test_srvctl_modules() {
    if [[ ! -f /etc/srvctl/modules.conf ]]
    then
        msg "Srvctl modules configuration"
        local tvtm trtm
        for dir in $SC_INSTALL_DIR/modules/*
        do
            tvtm="SC_USE_${dir##*/}"
            trtm=false
            if [[ -f $dir/module-condition.sh ]]
            then
                trtm="$(source "$dir/module-condition.sh")"
                if [[ $trtm == true ]]
                then
                    trtm=true
                else
                    trtm=false
                fi
                ntc "tested module: $tvtm=$trtm"
            fi
            #declare $tv=$tr
            echo "$tvtm=$trtm" >> /etc/srvctl/modules.conf
        done
    fi
}

#function hint_cms {
#    for sourcefile in $SC_INSTALL_DIR/ve-cms/*
#    do
#        [[ -f "$sourcefile" ]] && source "$sourcefile"
#    done
#}

