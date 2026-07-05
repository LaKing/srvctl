#!/bin/bash
## modules/gui/libs/spec.sh - compile the command spec for srvctl-gui.
##
## The only LIVE part of the otherwise dormant gui module (the install hook
## is disabled, see hooks/update-install-host.sh). Sourced by load_libs
## whenever SC_USE_GUI=true, which is every host (see module-condition.sh).
## make_commands_spec is called cross-module from
## modules/srvctl/commands/update-install.sh under "if $SC_USE_GUI".
##
## Output: /var/local/srvctl/commands.spec - one record per command, four
## fields joined by the multiplication sign U+00D7:
##     sourcepath×command×hint×syntax
## consumed by modules/gui/server.js (process_commands_spec). Enabled
## modules' command.sh files may contribute raw passthrough records via
## lines starting with the spec marker (format: ## spec //cat×cmd×hint×args).

## Append one spec record for a single command file ($1).
## Files marked root_only or interactive in their first 10 lines are skipped.
function make_commands_spec_on_file() {
    [[ ! -f $1 ]] && return
    head "$1" | grep -q 'root_only' && return
    head "$1" | grep -q '## interactive' && return
    local hintstr hintcmd command

    command="$(basename "$1")"
    ## FIXME(v4): hint grep lacks -m 1: two hint lines in a file head embed a
    ## newline into the record, which makes server.js throw at startup.
    hintstr="$(head "$1" | grep "$HINT")"
    ## FIXME(v4): the file operand makes grep ignore the head pipe, so a
    ## syntax marker anywhere in the file becomes this command's argument spec.
    hintcmd="$(head "$1" | grep -m 1 "$HEMP" "$1")"

    ## Strip the .sh extension and the fixed 7-character HINT/HEMP prefixes.
    command="${command:0: -3}"
    hintstr="${hintstr:7}"
    hintcmd="${hintcmd:7}"

    echo "$1×$command×$hintstr×$hintcmd" >> /var/local/srvctl/commands.spec

}

## Rebuild /var/local/srvctl/commands.spec from scratch: root custom
## commands, every module's commands, every user's custom commands, then
## the raw spec passthrough lines of enabled modules' command.sh files.
function make_commands_spec() {
    msg "Make user commands spec for srvctl-gui."
    rm -fr /var/local/srvctl/commands.spec

    local sourcefile dir homedir
    for sourcefile in /root/srvctl-includes/*.sh
    do
        make_commands_spec_on_file "$sourcefile"
    done

    ## FIXME(v4): iterates all modules regardless of enablement (unlike the
    ## spec-passthrough loop below), so commands of disabled modules end up
    ## in the spec and show up as GUI buttons that fail when clicked.
    for dir in $SC_MODULES
    do
        for sourcefile in "$dir"/commands/*.sh
        do
            make_commands_spec_on_file "$sourcefile"
        done
    done

    for homedir in /home/*
    do
        if [[ -d "$homedir/srvctl-includes" ]]
        then
            for sourcefile in "$homedir"/srvctl-includes/*.sh
            do
                make_commands_spec_on_file "$sourcefile"
            done
        fi
    done

    local tvhc module
    for dir in $SC_MODULES
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
    ## We don't read individual user commands
}
