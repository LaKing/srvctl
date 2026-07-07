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

    ## Raw datastore verbs typed as `sc <verb> ...`. WP-E.1: WRITES
    ## (new/put/cfg/del/add) require root + arguments; READS (get/out) stay
    ## open to any caller. Internal non-root reads (e.g. `cfg user
    ## container_list`) go through the bash verb wrappers in bashlib.sh, not
    ## this dispatch path, so they are unaffected. Previously '&&' bound
    ## tighter than '||', so only 'new' was root-gated and every other verb
    ## dispatched for ANY user. Full role-based gating is WP-E.2 (012 plan).
    if [[ $UID == 0 ]] && [[ $OPAS ]] && { [[ $CMD == 'new' ]] || [[ $CMD == 'put' ]] || [[ $CMD == 'cfg' ]] || [[ $CMD == 'del' ]] || [[ $CMD == 'add' ]]; }
    then
        # shellcheck disable=SC2086
        $CMD $OPAS
        exif "failed to exec '$CMD $OPAS'"
        return
    fi
    if [[ $CMD == 'get' ]] || [[ $CMD == 'out' ]]
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

## print the one-line hint for a command file, honoring its permission markers.
## VISIBILITY MIRRORS ENFORCEMENT (WP-E.2.b): the caller sees only what their
## role can run — root everything; operator operators_only + everyone; user
## everyone (+ owner_only, which is resource-scoped so always listed). hs_only
## is environment (SC_HOSTNET); reseller_only is transitional (removed in WP-F).
function hint_on_file {

    local file
    file="$1"

    [[ -f $file ]] || return 132

    ## resolve the caller's role once, memoized in SC_ROLE. Prefer sc_role
    ## (authlib.sh — gives the operator distinction from the datastore); if it
    ## is not loaded (early/completion paths), fall back to the root/non-root
    ## split from SC_UID0 so the listing still filters safely.
    if [[ -z ${SC_ROLE:-} ]]
    then
        command -v sc_role > /dev/null 2>&1 && sc_role > /dev/null 2>&1
        [[ ${SC_ROLE:-} ]] || if $SC_UID0; then SC_ROLE=root; else SC_ROLE=user; fi
    fi

    local hintstr command hintcmd hintexec data

    ## indexed path: permission filter + metadata from the SC_IDX_* arrays,
    ## no per-file greps. Byte-identical to the grep path below (proven by the
    ## bare-`sc` sandbox differential); the '## &&&' command is still executed
    ## at runtime, exactly as before.
    if $SC_IDX_BUILT && [[ -n ${SC_IDX_HINT[$file]+x} ]]
    then
        if [[ $SC_ROLE != root ]]
        then
            [[ ${SC_IDX_ROOT[$file]} ]] && return 133                              # root_only
            [[ ${SC_IDX_OPS[$file]} ]] && [[ $SC_ROLE != operator ]] && return 134 # operators_only -> hide from user
        fi
        ! [[ $SC_HOSTNET ]] && [[ ${SC_IDX_HS[$file]} ]] && return 134
        [[ $SC_ROLE != root ]] && ! [[ "${#SC_USER}" == 1 ]] && [[ ${SC_IDX_RES[$file]} ]] && return 134

        command="${file##*/}"
        hintstr="${SC_IDX_HINT[$file]}"
        hintcmd="${SC_IDX_SYNTAX[$file]}"   # empty == no '## @@@' (invariant)
        hintexec="${SC_IDX_DYNAMIC[$file]}" # empty == no '## &&&' (invariant)
        data=""
        [[ $hintexec ]] && data="[$(${hintexec} | tr '\n' '|')]"
        if [[ -z $hintcmd ]]
        then
            hint "${command:0: -3}" "$hintstr $data" "$file"
            complicate "${command:0: -3}"
        else
            hint "$hintcmd" "$hintstr $data" "$file"
            complicate "$hintcmd"
        fi
        return 0
    fi

    ## fallback (no index built, e.g. completion / single lookups): grep the
    ## markers directly, same role visibility as the indexed path above.
    if [[ $SC_ROLE != root ]]
    then
        head -n 20 "$file" | grep -q 'root_only' && return 133
        head -n 20 "$file" | grep -q 'operators_only' && [[ $SC_ROLE != operator ]] && return 134
    fi
    ! [[ $SC_HOSTNET ]] && head -n 20 "$file" | grep -q 'hs_only' && return 134
    [[ $SC_ROLE != root ]] && ! [[ "${#SC_USER}" == 1 ]] && head -n 20 "$file" | grep -q 'reseller_only' && return 134

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
    
    ## WP-D: parse every command file this listing will show in ONE node call,
    ## mirroring the loops below EXACTLY (custom root includes, enabled-module
    ## commands/*.sh, user includes, enabled-module command.sh). hint_on_file
    ## then reads the index instead of re-grepping each file 5+ times.
    local tvhc module
    local -a idx_paths=()
    local p
    if [[ -d /root/srvctl-includes ]]
    then for p in /root/srvctl-includes/*.sh; do [[ -f $p ]] && idx_paths+=("$p"); done
    fi
    for dir in $SC_MODULES
    do
        module="${dir##*/}"; tvhc="SC_USE_${module^^}"
        [[ ${!tvhc} == true ]] || continue
        for p in "$dir"/commands/*.sh; do [[ -f $p ]] && idx_paths+=("$p"); done
        [[ -f "$dir/command.sh" ]] && idx_paths+=("$dir/command.sh")
    done
    if [[ -d $SC_HOME/srvctl-includes ]] && [[ $SC_HOME != /root ]]
    then for p in "$SC_HOME"/srvctl-includes/*.sh; do [[ -f $p ]] && idx_paths+=("$p"); done
    fi
    build_command_index "${idx_paths[@]}"

    if [ -d /root/srvctl-includes ]
    then
        title "COMMAND - from root"
        for sourcefile in /root/srvctl-includes/*.sh
        do
            hint_on_file "$sourcefile"
        done
        title "COMMAND - from srvctl"
    fi

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
## ---- command index (WP-D): parse all command-file help metadata in ONE
## node call instead of grepping each file 4-5 times. commandindex.mjs is a
## faithful match of the $HINT/$HEMP/$HEXE/$HELP grep semantics (proven by
## modules/srvctl/selftest/commandindex.test.mjs, 190/190 over the real files);
## help_on_file/hint_on_file read these arrays, falling back to grep when the
## index was not built (e.g. single-command `sc help CMD`) or a path is absent.
## help_on_file consumes HINT+HELP; hint_on_file also consumes SYNTAX (@@@),
## DYNAMIC (&&&) and the ROOT/HS/RES permission booleans. commandindex.mjs
## guarantees @@@/&&& values are non-empty when present (parser test enforces
## it), so an EMPTY SC_IDX_SYNTAX/SC_IDX_DYNAMIC means the marker is ABSENT —
## the presence test the grep path did with `[[ -z $hintcmd ]]`.
declare -A SC_IDX_HINT SC_IDX_HELP SC_IDX_SYNTAX SC_IDX_DYNAMIC SC_IDX_ROOT SC_IDX_HS SC_IDX_RES SC_IDX_OPS
SC_IDX_BUILT=false

function build_command_index() {
    ## $@ = command-file paths. Populate the SC_IDX_* arrays keyed by path.
    SC_IDX_HINT=(); SC_IDX_HELP=(); SC_IDX_SYNTAX=(); SC_IDX_DYNAMIC=()
    SC_IDX_ROOT=(); SC_IDX_HS=(); SC_IDX_RES=(); SC_IDX_OPS=()
    SC_IDX_BUILT=false
    [[ $# -gt 0 ]] || return 0
    local tag path f1 f2 f3 f4 f5 f6 f7
    ## \x1f (US) delimiter, NOT tab: read collapses consecutive IFS-whitespace
    ## (tab), which would shift empty syntax/dynamic fields. See commandindex.mjs.
    ## Field order: hint syntax dynamic root_only hs_only reseller_only operators_only.
    while IFS=$'\x1f' read -r tag path f1 f2 f3 f4 f5 f6 f7
    do
        if [[ $tag == F ]]
        then
            SC_IDX_HINT[$path]="$f1"; SC_IDX_SYNTAX[$path]="$f2"; SC_IDX_DYNAMIC[$path]="$f3"
            SC_IDX_ROOT[$path]="$f4"; SC_IDX_HS[$path]="$f5"; SC_IDX_RES[$path]="$f6"; SC_IDX_OPS[$path]="$f7"
            [[ -n ${SC_IDX_HELP[$path]+x} ]] || SC_IDX_HELP[$path]=""
        elif [[ $tag == H ]]
        then
            if [[ -n ${SC_IDX_HELP[$path]:-} ]]
            then SC_IDX_HELP[$path]="${SC_IDX_HELP[$path]}"$'\n'"$f1"
            else SC_IDX_HELP[$path]="$f1"
            fi
        fi
    done < <(/bin/node "$SC_INSTALL_DIR/modules/srvctl/lib/commandindex.mjs" --bash "$@" 2> /dev/null)
    ## only trust the index if node actually produced entries for the inputs
    [[ ${#SC_IDX_HINT[@]} -gt 0 ]] && SC_IDX_BUILT=true
}

function help_on_file {
    [[ -f "$1" ]] || return 133

    local command hintstr
    command="${1##*/}"   # basename, no fork

    if $SC_IDX_BUILT && [[ -n ${SC_IDX_HINT[$1]+x} ]]
    then
        hint "${command:0: -3}" "${SC_IDX_HINT[$1]}" "$1"
        printf "${YELLOW}%-4s" ""
        echo ''
        [[ -n ${SC_IDX_HELP[$1]:-} ]] && printf '%s\n' "${SC_IDX_HELP[$1]}"
        printf "${CLEAR}%-4s" ""
        echo ""
        return 0
    fi

    ## fallback: original per-file grep
    hintstr="$(head "$1" | grep "$HINT")"
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

        ## WP-D: parse every command file's help metadata in ONE node call, so
        ## the help_on_file calls below read the index instead of re-grepping
        ## each file. Collect exactly the paths the loops will render, in order.
        local -a idx_paths=()
        local p
        if [[ -d /root/srvctl-includes ]]
        then for p in /root/srvctl-includes/*.sh; do [[ -f $p ]] && idx_paths+=("$p"); done
        fi
        for dir in $SC_MODULES
        do for p in "$dir"/commands/*.sh; do [[ -f $p ]] && idx_paths+=("$p"); done
        done
        if [[ -d $SC_HOME/srvctl-includes ]] && [[ $SC_HOME != /root ]]
        then for p in "$SC_HOME"/srvctl-includes/*.sh; do [[ -f $p ]] && idx_paths+=("$p"); done
        fi
        build_command_index "${idx_paths[@]}"

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
    ## legacy monolithic datastore (pre-migration): world-readable json
    chmod 644 "$SC_DATASTORE_RW_DIR"/*.json 2> /dev/null
    ## v4 file-per-entity datastore: type dirs traversable, entity records
    ## world-readable so non-root `sc get` can read them (as v3's *.json were).
    ## NB: full per-entity permission model (keys under users/<u>/, cert/) is a
    ## VM-test item before live rollout.
    local dsdir
    for dsdir in hosts users containers
    do
        [[ -d "$SC_DATASTORE_RW_DIR/$dsdir" ]] || continue
        chmod 755 "$SC_DATASTORE_RW_DIR/$dsdir"
        chmod 644 "$SC_DATASTORE_RW_DIR/$dsdir"/*.json 2> /dev/null
    done

    [[ -d "$SC_MOUNTS_DIR" ]] && chmod 700 "$SC_MOUNTS_DIR"
    [[ -d "$SC_ROOTFS_DIR" ]] && chmod 700 "$SC_ROOTFS_DIR"
    
}

