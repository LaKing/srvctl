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
#readonly CLEAR='\e[0m'
## functions common to all areas of srvctl
function hint {
    local cmd hint file
    cmd="$1"
    hint="$2"
    file="$3"
    
    ## print formatted hint
    if $DEBUG && [[ $CMD == help ]]
    then
        printf "${BLUE}%-48s${CLEAR}" "   $file"
        echo ''
    fi
    
    printf "${GREEN}%-40s${CLEAR}" "   $cmd"
    printf "${GREEN}%-48s${CLEAR}" " $hint"
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
    local tvll module
    
    for dir in $SC_MODULES
    do
        module="${dir##*/}"
        tvll="SC_USE_${module^^}"
        if [[ ${!tvll} == true ]]
        then
            for sourcefile in $dir/libs/*
            do
                debug "@lib ${dir##*/} ${sourcefile##*/}"
                
                ## dynamic source
                # shellcheck disable=SC1090
                [[ -f $sourcefile ]] && source "$sourcefile"
            done
        fi
    done
}

## outdated - modules shall be taken from SC_MODULES
#function run_module_hook { ## module hook
#    local dir hook
#    dir="$SC_INSTALL_DIR/modules/$1"
#    hook="$2"
#
#    if [[ -f $dir/hooks/$hook.sh ]]
#    then
#
#        debug "@hook ${dir##*/} $hook"
#        ## dynamic source
#        # shellcheck disable=SC1090
#        source "$dir/hooks/$hook.sh"
#        exif "$dir hook '$hook' failed"
#    fi
#}

function run_hook {
    local hook tvrh module
    hook="$1"
    for dir in $SC_MODULES
    do
        module="${dir##*/}"
        tvrh="SC_USE_${module^^}"
        
        if [[ ${!tvrh} == true ]]
        then
            
            ## find and call hooks
            if [[ -f $dir/hooks/$hook.sh ]]
            then
                
                debug "@hook ${dir##*/} $hook"
                ## dynamic source
                # shellcheck disable=SC1090
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
    
    local tvrc module
    
    ## call a srvctl function
    if [[ $UID == 0 ]] && [[ $OPAS ]] && [[ $CMD == 'exec-function' ]]
    then
        $OPAS
        exif "failed to exec '$OPAS'"
        return
    fi
    
    ## call a srvctl data function
    if [[ $UID == 0 ]] && [[ $OPAS ]] && [[ $CMD == 'new' ]] ||  [[ $CMD == 'get' ]] ||  [[ $CMD == 'put' ]] ||  [[ $CMD == 'out' ]] ||  [[ $CMD == 'cfg' ]] ||  [[ $CMD == 'del' ]]  ||  [[ $CMD == 'fix' ]]
    then
        # shellcheck disable=SC2086
        $CMD $OPAS
        exif "failed to exec '$CMD $OPAS'"
        return
    fi
    
    ## permissions will determine the visibility of these commands
    if [[ -f /root/srvctl-includes/$CMD.sh ]]
    then
        ## dynamic source
        # shellcheck disable=SC1090
        source "/root/srvctl-includes/$CMD.sh"
        exif "'$CMD' failed"
        return
    fi
    
    ## command from a module
    for dir in $SC_MODULES
    do
        
        module="${dir##*/}"
        tvrc="SC_USE_${module^^}"
        
        if [[ ${!tvrc} == true ]]
        then
            
            ## find and run commands
            if [[ -f $dir/commands/$CMD.sh ]]
            then
                ## dynamic source
                # shellcheck disable=SC1090
                source "$dir/commands/$CMD.sh"
                exif "'$CMD' failed ($dir)"
                return
            fi
        fi
    done
    
    ## custom by user
    if [[ -f $SC_HOME/srvctl-includes/$CMD.sh ]] && [[ $SC_HOME != /root ]]
    then
        ## dynamic source
        # shellcheck disable=SC1090
        source "$SC_HOME/srvctl-includes/$CMD.sh"
        exif "'$CMD' failed"
        return
    fi
    
    
    debug "@default-command"
    
    for dir in $SC_MODULES
    do
        
        module="${dir##*/}"
        tvrc="SC_USE_${module^^}"
        
        if [[ ${!tvrc} == true ]]
        then
            
            ## try to find and run default command
            if [[ -f $dir/command.sh ]]
            then
                debug "@command.sh ${dir##*/}"
                ## dynamic source
                # shellcheck disable=SC1090
                source "$dir/command.sh"
            fi
        fi
    done
    
    return 250
}

## by default complicate takes no action, but this functuion can be re-defined
function complicate() {
    echo "$1" > /dev/null
}

function hint_on_file {
    
    [[ -f $1 ]] || return 132
    ## root_only: if not root, and file marked as root_only skip this item
    ! $SC_ROOT && head "$1" | grep -q 'root_only' && return 133
    ## if not on a containerfarm host
    ! [[ $SC_HOSTNET ]] && head "$1" | grep -q 'hs_only' && return 134
    ## is user is not a reseller
    ! $SC_ROOT && ! [[ "${#SC_USER}" == 1 ]] && head "$1" | grep -q 'reseller_only' && return 134
    
    #! $SC_ON_VE && head "$1" | grep -q 've_only' && return 135
    
    local hintstr command hintcmd
    
    hintstr="$(head "$1" | grep -m 1 "$HINT")"
    command="$(basename "$1")"
    hintcmd="$(head "$1" | grep -m 1 "$HEMP" "$1")"
    
    if [[ -z $hintcmd ]]
    then
        hint "${command:0: -3}" "${hintstr:7}" "$1"
        complicate "${command:0: -3}"
    else
        hint "${hintcmd:7}" "${hintstr:7}" "$1"
        complicate "${hintcmd:7}"
    fi
}

function hint_commands {
    
    prg "Usage: srvctl command [argument]"
    prg "  currently available commands for $SC_USER"
    if [[ -d $SC_HOME/srvctl-includes ]] && [[ $SC_HOME != /root ]]
    then
        title "COMMAND"
    else
        echo ""
    fi
    
    if [ -d /root/srvctl-includes ]
    then
        title "COMMAND - from root"
        for sourcefile in /root/srvctl-includes/*.sh
        do
            hint_on_file "$sourcefile"
        done
        title "COMMAND - from srvctl"
    fi
    
    local tvhc module
    for dir in $SC_MODULES
    do
        
        module="${dir##*/}"
        tvhc="SC_USE_${module^^}"
        
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
    
    echo ''
    
    for dir in $SC_MODULES
    do
        module="${dir##*/}"
        tvhc="SC_USE_${module^^}"
        
        if [[ ${!tvhc} == true ]]
        then
            if [[ -f "$dir/command.sh" ]]
            then
                hint_on_file "$dir/command.sh"
            fi
        fi
    done
    
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
    hint "${command:0: -3}" "${hintstr:7}" "$1"
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
            title "COMMAND - from root"
            for sourcefile in /root/srvctl-includes/*.sh
            do
                help_on_file "$sourcefile"
            done
            title "COMMAND - from srvctl"
        fi
        
        for dir in $SC_MODULES
        do
            for sourcefile in $dir/commands/*.sh
            do
                help_on_file "$sourcefile"
            done
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
        
        for dir in $SC_MODULES
        do
            if [[ -f $dir/commands/$arg ]]
            then
                help_on_file "$dir/commands/$arg.sh"
                prg "srvctl v3 command"
                return
            fi
        done
        
        if [[ -f $SC_HOME/srvctl-includes/$arg.sh ]] && [[ $SC_HOME != /root ]]
        then
            help_on_file "$SC_HOME/srvctl-includes/$arg.sh"
            prg "Custom command defined in $SC_HOME/srvctl-includes/$arg.sh"
            return
        fi
        
        err "Pardon? '$ARG' is not a command"
        return 46
    fi
    
}

function test_srvctl_modules() {
    
    local conf
    
    conf=/var/local/srvctl/modules.conf
    
    if [[ $USER == root ]]
    then
        #conf=/var/local/srvctl/modules.conf
        mkdir -p /var/local/srvctl/
    fi
    
    if [[ $SC_HOME ]]
    then
        conf="$SC_HOME/.srvctl/modules.conf"
        mkdir -p "$SC_HOME/.srvctl"
    fi
    
    if [[ ! -f $conf ]] || [[ $CMD == update-install ]] || [[ $CMD == test-modules ]]
    then
        msg "Srvctl modules configuration"
        
        ## test value / test result on tested module
        local tvtm trtm module
        for dir in $SC_MODULES
        do
            module="${dir##*/}"
            tvtm="SC_USE_${module^^}"
            trtm=false
            if [[ -f $dir/module-condition.sh ]]
            then
                # shellcheck disable=SC1090
                trtm="$(source "$dir/module-condition.sh")"
                if [[ $trtm == true ]]
                then
                    trtm=true
                else
                    trtm=false
                fi
                ntc "tested module: $tvtm=$trtm"
            else
                err "Module $module has no condition file in $dir"
            fi
            #declare $tv=$tr
            echo "export $tvtm=$trtm" >> "$conf"
        done
    fi
    
    if [[ $CMD == 'test-modules' ]]
    then
        msg "srvctl modules selected"
        exit 0
    fi
    
    if [[ -f /var/local/srvctl/modules.conf ]]
    then
        debug "@source /var/local/srvctl/modules.conf"
        source /var/local/srvctl/modules.conf
    fi
    
    if [[ -f $conf ]]
    then
        debug "@source $conf"
        ## dynamic source
        # shellcheck disable=SC1090
        source "$conf"
    fi
    
    for dir in $SC_MODULES
    do
        module="${dir##*/}"
        export "SC_USE_${module^^}"
        readonly "SC_USE_${module^^}"
    done
    
}

function set_permissions() {
    msg "Set permissions."
    
    chmod -R 600 /etc/srvctl
    chmod 755 /etc/srvctl
    chmod 644 /etc/srvctl/*.conf
    chmod 644 /etc/srvctl/*.json
    
    chmod -R 600 "$SC_DATASTORE_RW_DIR"
    
    chmod 755 "$SC_DATASTORE_RW_DIR"
    chmod 644 "$SC_DATASTORE_RW_DIR"/*.json
    
    [[ -d "$SC_MOUNTS_DIR" ]] && chmod 700 "$SC_MOUNTS_DIR"
    [[ -d "$SC_ROOTFS_DIR" ]] && chmod 700 "$SC_ROOTFS_DIR"
    
}

#function hint_cms {
#    for sourcefile in $SC_INSTALL_DIR/ve-cms/*
#    do
#        [[ -f "$sourcefile" ]] && source "$sourcefile"
#    done
#}


