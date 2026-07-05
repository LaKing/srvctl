#!/bin/bash

##
##   commonlib.sh — the srvctl engine: module iteration, hook execution,
##   command dispatch, and help/hint generation.
##
##   Sourced by init.sh after lablib.sh. Operates on the module list in
##   SC_MODULES (set by srvctl.sh) gated per-module by the cached
##   SC_USE_<MODULE> flags (see test_srvctl_modules).
##

## run only with srvctl
[[ $SRVCTL ]] || exit 10

## Help metadata markers, read from the head of command files:
## optional - help execution main parameter - to allow optional arguments
readonly HEMP='## @@@'
## mandatory - the single hint string (must be within the first 10 lines)
readonly HINT='## @en'
## mandatory - the multistring help
readonly HELP='## &en'
## optional - help dynamically executed
readonly HEXE='## &&&'

## functions common to all areas of srvctl

## print one formatted hint line: 3-space indent, %-40s command column,
## %-48s hint column. Do not change the layout — generate_completion
## captures it and modules/srvctl/completion.sh parses the capture.
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

## source every libs/* file of every enabled module into the CLI shell.
## Runs once at init (init.sh), after the help-only breakout.
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

## source hooks/<name>.sh of every enabled module, in SC_MODULES order.
## A hook that exits nonzero (even via a trailing failed conditional)
## aborts the whole CLI through exif — hooks must end cleanly.
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

## run the pre-X, X, post-X hook triplet in order
function run_hooks {
    run_hook "pre-$1"
    run_hook "$1"
    run_hook "post-$1"
}

## Command dispatch. Precedence (first match wins, all sourced in THIS shell):
##   exec-function -> datastore verbs -> /root/srvctl-includes ->
##   module commands/ -> ~/srvctl-includes (non-root) -> module command.sh
## Returns 54 when no command was given, 250 when nothing matched.
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
    ## FIXME(v4): operator precedence — && binds tighter than ||, so the
    ## root-with-arguments guard applies to 'new' only; get/put/out/cfg/del/
    ## add match for ANY user with any argument count. Not changed tonight:
    ## non-root reads via 'sc get ...' may be in real use; the v4 dispatcher
    ## must gate these verbs by declared policy instead (012-permission plan).
    if [[ $UID == 0 ]] && [[ $OPAS ]] && [[ $CMD == 'new' ]] ||  [[ $CMD == 'get' ]] ||  [[ $CMD == 'put' ]] ||  [[ $CMD == 'out' ]] ||  [[ $CMD == 'cfg' ]] ||  [[ $CMD == 'del' ]]  ||  [[ $CMD == 'add' ]]
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

## print the one-line hint for a command file, honoring its permission
## markers (root_only/hs_only/reseller_only within the first 20 lines).
function hint_on_file {

    local file
    file="$1"

    [[ -f $file ]] || return 132
    ## root_only: if not root, and file marked as root_only skip this item
    ! $SC_UID0 && head -n 20 "$file" | grep -q 'root_only' && return 133
    ## if not on a containerfarm host
    ! [[ $SC_HOSTNET ]] && head -n 20 "$file" | grep -q 'hs_only' && return 134
    ## is user is not a reseller
    ! $SC_UID0 && ! [[ "${#SC_USER}" == 1 ]] && head -n 20 "$file" | grep -q 'reseller_only' && return 134

    local hintstr command hintcmd hintexec data

    ## NOTE: for HEMP and HEXE below, grep receives "$file" as an operand,
    ## so the head-limited stdin is ignored and the WHOLE file is searched.
    ## This is load-bearing: add-ve.sh has '## &&&' at line 13 and
    ## customize.sh has '## @@@' at line 41 — do not "fix" the pipe without
    ## migrating those files.
    ## FIXME(v4): a '## &&&' line ANYWHERE in a command file (heredocs
    ## included) is executed via command substitution below, on every bare
    ## 'sc', mistyped command, and completion run. v4 should build help from
    ## an index with an enforced header contract instead.
    hintstr="$(head "$file" | grep -m 1 "$HINT")"
    command="$(basename "$file")"
    hintcmd="$(head "$file" | grep -m 1 "$HEMP" "$file")"

    data=""
    hintexec="$(head "$file" | grep -m 1 "$HEXE" "$file")"
    if [[ $hintexec ]]
    then
        data="[$(${hintexec:7} | tr '\n' '|')]"
    fi
    
    if [[ -z $hintcmd ]]
    then
        hint "${command:0: -3}" "${hintstr:7} $data" "$file"
        complicate "${command:0: -3}"
    else
        hint "${hintcmd:7}" "${hintstr:7} $data" "$file"
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

## print the multi-line help block of one command file
## (multiple '## @en' lines render with raw markers — customize.sh has two;
## kept as-is, output-identical)
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

## full help listing (sc help) or per-command help (sc help COMMAND)
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

        ## FIXME(v4): unlike hint_commands, this full listing skips the
        ## SC_USE_* module filter and the root_only/hs_only permission
        ## filters — disabled-module and root-only commands are documented
        ## to everyone. Kept tonight (output-changing); align in v4.
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
            ## bugfix(v4-polish): was '[[ -f $dir/commands/$arg ]]' (missing
            ## .sh), which never matched — per-command help for module
            ## commands always fell through to "Pardon?".
            if [[ -f $dir/commands/$arg.sh ]]
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

## Decide which modules are enabled. Each module's module-condition.sh is
## evaluated in a subshell and must print "true" to enable the module.
## Results are cached as 'export SC_USE_<MODULE>=<bool>' lines in
## ~/.srvctl/modules.conf (regenerated when missing, or by update-install /
## test-modules); the legacy /var/local/srvctl/modules.conf is sourced first.
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

        ## bugfix(v4-polish): start from an empty cache. This used to
        ## append-only, so every update-install grew the file by another
        ## full block and stale SC_USE_* entries of removed modules
        ## persisted forever (last-wins kept current modules correct).
        : > "$conf"

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

## normalize ownership-sensitive modes on /etc/srvctl and the datastore
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

